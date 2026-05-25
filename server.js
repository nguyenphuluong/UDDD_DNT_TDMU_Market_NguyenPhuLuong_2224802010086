const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const tls = require("tls");
const { URL } = require("url");

function loadEnvFile() {
  const envPath = path.join(__dirname, ".env");
  if (!fs.existsSync(envPath)) return;
  const lines = fs.readFileSync(envPath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) continue;
    const key = match[1];
    let value = match[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    process.env[key] ??= value;
  }
}

loadEnvFile();

const { readDb, writeDb } = require("./storage");

const PORT = process.env.PORT || 3000;
const PUBLIC_DIR = path.join(__dirname, "public");
const UPLOAD_DIR = path.join(PUBLIC_DIR, "uploads");
const TOKEN_SECRET = process.env.TOKEN_SECRET || "tdmu-marketplace-demo-secret";
const STUDENT_EMAIL_DOMAIN = "@student.tdmu.edu.vn";
const CODE_TTL_MS = 10 * 60 * 1000;

const clients = new Map();

function ensureUploadDir() {
  if (!fs.existsSync(UPLOAD_DIR)) fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

function id(prefix) {
  return `${prefix}_${crypto.randomBytes(8).toString("hex")}`;
}

function hashPassword(password) {
  return crypto.createHash("sha256").update(String(password)).digest("hex");
}

function signToken(payload) {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = crypto.createHmac("sha256", TOKEN_SECRET).update(body).digest("base64url");
  return `${body}.${signature}`;
}

function verifyToken(token) {
  if (!token || !token.includes(".")) return null;
  const [body, signature] = token.split(".");
  const expected = crypto.createHmac("sha256", TOKEN_SECRET).update(body).digest("base64url");
  if (Buffer.byteLength(signature) !== Buffer.byteLength(expected)) return null;
  if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return null;
  try {
    return JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

function send(res, status, data, headers = {}) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    ...headers
  });
  res.end(JSON.stringify(data));
}

function sendError(res, status, message) {
  send(res, status, { error: message });
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", chunk => {
      body += chunk;
      if (body.length > 5_000_000) {
        req.destroy();
        reject(new Error("Payload qua lon"));
      }
    });
    req.on("end", () => {
      if (!body) return resolve({});
      try {
        resolve(JSON.parse(body));
      } catch {
        reject(new Error("JSON khong hop le"));
      }
    });
  });
}

function publicUser(user) {
  if (!user) return null;
  const { passwordHash, ...safe } = user;
  return safe;
}

function initials(name) {
  return String(name || "SV").trim().split(/\s+/).map(part => part[0]).join("").slice(-2).toUpperCase();
}

function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function isStudentEmail(email) {
  return normalizeEmail(email).endsWith(STUDENT_EMAIL_DOMAIN);
}

function cleanExpiredAuthCodes(db) {
  const now = Date.now();
  db.authCodes = (db.authCodes || []).filter(item => new Date(item.expiresAt).getTime() > now);
}

function createAuthCode(db, email, purpose, payload = {}) {
  cleanExpiredAuthCodes(db);
  const code = String(crypto.randomInt(100000, 1000000));
  const now = Date.now();
  db.authCodes = db.authCodes.filter(item => !(item.email === email && item.purpose === purpose));
  db.authCodes.unshift({
    id: id("code"),
    email,
    purpose,
    code,
    payload,
    createdAt: new Date(now).toISOString(),
    expiresAt: new Date(now + CODE_TTL_MS).toISOString()
  });
  return code;
}

function consumeAuthCode(db, email, purpose, code) {
  cleanExpiredAuthCodes(db);
  const value = String(code || "").trim();
  const index = db.authCodes.findIndex(item =>
    item.email === email &&
    item.purpose === purpose &&
    item.code === value
  );
  if (index === -1) return null;
  const [record] = db.authCodes.splice(index, 1);
  return record;
}

function createSmtpReader(socket) {
  let buffer = "";
  let current = [];
  const waiting = [];

  function rejectAll(error) {
    while (waiting.length) waiting.shift().reject(error);
  }

  function flush() {
    while (waiting.length) {
      const newlineIndex = buffer.indexOf("\n");
      if (newlineIndex === -1) return;
      const raw = buffer.slice(0, newlineIndex);
      buffer = buffer.slice(newlineIndex + 1);
      const line = raw.replace(/\r$/, "");
      current.push(line);
      if (/^\d{3} /.test(line)) {
        const reply = current.join("\n");
        current = [];
        waiting.shift().resolve(reply);
      }
    }
  }

  socket.on("data", chunk => {
    buffer += chunk.toString("utf8");
    flush();
  });
  socket.on("error", rejectAll);
  socket.on("timeout", () => rejectAll(new Error("SMTP timeout")));
  socket.on("close", () => rejectAll(new Error("SMTP connection closed")));

  return () => new Promise((resolve, reject) => {
    waiting.push({ resolve, reject });
    flush();
  });
}

function smtpReplyCode(reply) {
  return Number(String(reply).slice(0, 3));
}

async function expectSmtp(reader, allowedCodes) {
  const reply = await reader();
  if (!allowedCodes.includes(smtpReplyCode(reply))) {
    throw new Error(`SMTP error: ${reply}`);
  }
  return reply;
}

async function smtpCommand(socket, reader, command, allowedCodes) {
  socket.write(`${command}\r\n`);
  return expectSmtp(reader, allowedCodes);
}

function smtpDataText(text) {
  return String(text).replace(/\r?\n/g, "\r\n").replace(/^\./gm, "..");
}

async function sendGmailMail({ to, subject, text }) {
  const user = mailUser();
  const pass = mailPassword();
  if (!user || !pass) return { sent: false, reason: "missing_credentials" };

  const socket = tls.connect({
    host: "smtp.gmail.com",
    port: 465,
    servername: "smtp.gmail.com"
  });
  socket.setTimeout(12000);
  const reader = createSmtpReader(socket);

  await new Promise((resolve, reject) => {
    socket.once("secureConnect", resolve);
    socket.once("error", reject);
  });

  await expectSmtp(reader, [220]);
  await smtpCommand(socket, reader, "EHLO localhost", [250]);
  await smtpCommand(socket, reader, "AUTH LOGIN", [334]);
  await smtpCommand(socket, reader, Buffer.from(user).toString("base64"), [334]);
  await smtpCommand(socket, reader, Buffer.from(pass).toString("base64"), [235]);
  await smtpCommand(socket, reader, `MAIL FROM:<${user}>`, [250]);
  await smtpCommand(socket, reader, `RCPT TO:<${to}>`, [250, 251]);
  await smtpCommand(socket, reader, "DATA", [354]);

  const message = [
    `From: TDMU Market <${user}>`,
    `To: ${to}`,
    `Subject: ${subject}`,
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=utf-8",
    "Content-Transfer-Encoding: 8bit",
    "",
    smtpDataText(text),
    "."
  ].join("\r\n");
  socket.write(`${message}\r\n`);
  await expectSmtp(reader, [250]);
  await smtpCommand(socket, reader, "QUIT", [221]);
  socket.end();
  return { sent: true };
}

function mailUser() {
  const value = process.env.SMTP_USER || process.env.GMAIL_USER;
  return isConfiguredMailValue(value) ? value : "";
}

function mailPassword() {
  const value = process.env.SMTP_PASS || process.env.GMAIL_APP_PASSWORD;
  return isConfiguredMailValue(value) ? value : "";
}

function isConfiguredMailValue(value) {
  const text = String(value || "").trim();
  return text && !text.startsWith("your_") && !text.includes("app_password");
}

function canIssueAuthCode() {
  return Boolean(mailUser() && mailPassword()) || process.env.AUTH_DEV_CODE === "true";
}

function requireAuthCodeDelivery(res) {
  if (canIssueAuthCode()) return true;
  sendError(
    res,
    500,
    "Chua cau hinh Gmail SMTP. Vui long cai GMAIL_USER va GMAIL_APP_PASSWORD de gui ma ve email."
  );
  return false;
}

async function sendAuthCode(email, purpose, code) {
  const title = purpose === "forgot" ? "Dat lai mat khau" : "Xac nhan dang ky";
  const text = [
    `Ma xac nhan TDMU Market cua ban la: ${code}`,
    "",
    "Ma co hieu luc trong 10 phut.",
    "Neu ban khong yeu cau thao tac nay, vui long bo qua email."
  ].join("\n");
  const result = await sendGmailMail({
    to: email,
    subject: `TDMU Market - ${title}`,
    text
  });
  if (!result.sent && process.env.AUTH_DEV_CODE === "true") {
    console.log(`[auth-code:${purpose}] ${email} -> ${code}`);
  }
  return result;
}

async function sendAuthCodeResponse(res, email, purpose, code) {
  try {
    const mail = await sendAuthCode(email, purpose, code);
    if (!mail.sent && process.env.AUTH_DEV_CODE !== "true") {
      return sendError(
        res,
        500,
        "Chua cau hinh Gmail SMTP. Vui long cai GMAIL_USER va GMAIL_APP_PASSWORD de gui ma ve email."
      );
    }
    const data = {
      ok: true,
      sent: mail.sent,
      expiresInMinutes: CODE_TTL_MS / 60_000
    };
    if (!mail.sent) data.devCode = code;
    return send(res, 200, data);
  } catch (error) {
    return sendError(res, 502, `Khong gui duoc ma xac nhan: ${error.message}`);
  }
}

function addNotification(db, userId, type, title, message, link = "notifications", extra = {}) {
  db.notifications ||= [];
  const notification = {
    id: id("n"),
    userId,
    type,
    title,
    message,
    link,
    ...extra,
    read: false,
    createdAt: new Date().toISOString()
  };
  db.notifications.unshift(notification);
  return notification;
}

function otherParticipantId(chat, userId) {
  return chat.buyerId === userId ? chat.sellerId : chat.buyerId;
}

function unreadMessagesForChat(db, chat, userId) {
  const readBy = chat.readBy || {};
  const lastReadAt = new Date(readBy[userId] || chat.createdAt || 0);
  return db.messages.filter(message =>
    message.chatId === chat.id &&
    message.senderId !== userId &&
    new Date(message.createdAt) > lastReadAt
  ).length;
}

function markChatPairRead(db, chat, user) {
  const now = new Date().toISOString();
  const otherId = otherParticipantId(chat, user.id);
  const other = db.users.find(item => item.id === otherId);
  const relatedChats = db.chats.filter(item =>
    (item.buyerId === user.id && item.sellerId === otherId) ||
    (item.sellerId === user.id && item.buyerId === otherId)
  );
  for (const item of relatedChats) {
    item.readBy ||= {};
    item.readBy[user.id] = now;
  }
  for (const item of db.notifications || []) {
    if (item.userId !== user.id || item.type !== "chat") continue;
    if (
      item.chatId === chat.id ||
      item.senderId === otherId ||
      (!item.chatId && other?.name && String(item.message || "").startsWith(`${other.name}:`))
    ) {
      item.read = true;
    }
  }
}

function removeProduct(db, productId) {
  const productIndex = db.products.findIndex(item => item.id === productId);
  if (productIndex === -1) return null;
  const [product] = db.products.splice(productIndex, 1);
  const removedChatIds = db.chats.filter(chat => chat.productId === productId).map(chat => chat.id);
  db.favorites = db.favorites.filter(item => item.productId !== productId);
  db.chats = db.chats.filter(chat => chat.productId !== productId);
  db.messages = db.messages.filter(message => !removedChatIds.includes(message.chatId));
  return product;
}

function removeUser(db, userId) {
  const index = db.users.findIndex(item => item.id === userId);
  if (index === -1) return null;
  const [user] = db.users.splice(index, 1);
  const productIds = db.products.filter(product => product.sellerId === userId).map(product => product.id);
  for (const productId of productIds) removeProduct(db, productId);
  const chatIds = db.chats
    .filter(chat => chat.buyerId === userId || chat.sellerId === userId)
    .map(chat => chat.id);
  db.chats = db.chats.filter(chat => !chatIds.includes(chat.id));
  db.messages = db.messages.filter(message => message.senderId !== userId && !chatIds.includes(message.chatId));
  db.favorites = db.favorites.filter(item => item.userId !== userId && !productIds.includes(item.productId));
  db.cartItems = db.cartItems.filter(item => item.userId !== userId && !productIds.includes(item.productId));
  db.reviews = db.reviews.filter(item => item.buyerId !== userId && item.sellerId !== userId);
  db.notifications = db.notifications.filter(item => item.userId !== userId);
  db.orders = db.orders.filter(order =>
    order.userId !== userId &&
    !(order.items || []).some(item => item.sellerId === userId)
  );
  return user;
}

function requireAuth(req, res, db) {
  const header = req.headers.authorization || "";
  const tokenFromHeader = header.startsWith("Bearer ") ? header.slice(7) : null;
  const tokenFromQuery = new URL(req.url, `http://${req.headers.host}`).searchParams.get("token");
  const token = tokenFromHeader || tokenFromQuery;
  const payload = verifyToken(token);
  if (!payload) {
    sendError(res, 401, "Can dang nhap");
    return null;
  }
  const user = db.users.find(item => item.id === payload.id);
  if (!user) {
    sendError(res, 401, "Tai khoan khong ton tai");
    return null;
  }
  if (user.status === "blocked") {
    sendError(res, 403, "Tai khoan da bi khoa");
    return null;
  }
  return user;
}

function enrichProduct(db, product, viewerId) {
  const seller = db.users.find(user => user.id === product.sellerId);
  return {
    ...product,
    seller: publicUser(seller),
    favorite: Boolean(db.favorites.find(item => item.userId === viewerId && item.productId === product.id)),
    reviewCount: db.reviews.filter(review => review.sellerId === product.sellerId).length
  };
}

function getViewer(req, db) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  const payload = verifyToken(token);
  return payload ? db.users.find(user => user.id === payload.id) : null;
}

function matchesProduct(product, query) {
  const text = `${product.title} ${product.description} ${product.category} ${product.location}`.toLowerCase();
  return text.includes(query.toLowerCase());
}

function emitChat(chatId, event, data) {
  const chatClients = clients.get(chatId);
  if (!chatClients) return;
  for (const res of chatClients) {
    res.write(`event: ${event}\n`);
    res.write(`data: ${JSON.stringify(data)}\n\n`);
  }
}

function serveStatic(req, res, pathname) {
  const requested = pathname === "/" ? "/index.html" : pathname;
  const filePath = path.normalize(path.join(PUBLIC_DIR, requested));
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    res.writeHead(404);
    res.end("Not found");
    return;
  }
  const ext = path.extname(filePath);
  const types = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp"
  };
  res.writeHead(200, {
    "Content-Type": types[ext] || "application/octet-stream",
    "Cache-Control": "no-store"
  });
  fs.createReadStream(filePath).pipe(res);
}

async function handleApi(req, res, url) {
  const db = await readDb();
  const method = req.method;
  const pathname = url.pathname;

  if (method === "POST" && pathname === "/api/auth/login") {
    const body = await parseBody(req);
    const user = db.users.find(item => item.email.toLowerCase() === String(body.email || "").toLowerCase());
    if (!user || user.passwordHash !== hashPassword(body.password || "")) {
      return sendError(res, 401, "Email hoac mat khau khong dung");
    }
    if (user.status === "blocked") {
      return sendError(res, 403, "Tai khoan da bi khoa");
    }
    const token = signToken({ id: user.id, role: user.role, createdAt: Date.now() });
    return send(res, 200, { token, user: publicUser(user) });
  }

  if (method === "POST" && pathname === "/api/auth/register/request-code") {
    const body = await parseBody(req);
    const email = normalizeEmail(body.email);
    const name = String(body.name || "").trim();
    const studentId = String(body.studentId || "").trim();
    const major = String(body.major || "Sinh vien TDMU").trim();
    const password = String(body.password || "");

    if (!name || !email || !studentId || !password) {
      return sendError(res, 400, "Vui long nhap du thong tin");
    }
    if (!isStudentEmail(email)) {
      return sendError(res, 400, `Chi chap nhan email ${STUDENT_EMAIL_DOMAIN}`);
    }
    if (password.length < 6) {
      return sendError(res, 400, "Mat khau can it nhat 6 ky tu");
    }
    if (db.users.some(user => user.email.toLowerCase() === email)) {
      return sendError(res, 409, "Email da ton tai");
    }
    if (!requireAuthCodeDelivery(res)) return;

    const code = createAuthCode(db, email, "register", {
      name,
      studentId,
      major,
      passwordHash: hashPassword(password)
    });
    await writeDb(db);
    return sendAuthCodeResponse(res, email, "register", code);
  }

  if (method === "POST" && pathname === "/api/auth/register/verify") {
    const body = await parseBody(req);
    const email = normalizeEmail(body.email);
    if (!email || !body.code) return sendError(res, 400, "Vui long nhap ma xac nhan");
    if (db.users.some(user => user.email.toLowerCase() === email)) {
      return sendError(res, 409, "Email da ton tai");
    }

    const record = consumeAuthCode(db, email, "register", body.code);
    if (!record) return sendError(res, 400, "Ma xac nhan khong dung hoac da het han");

    const payload = record.payload || {};
    if (!payload.passwordHash) return sendError(res, 400, "Thong tin dang ky khong hop le");
    const user = {
      id: id("u"),
      name: String(payload.name || "Sinh vien TDMU").trim(),
      email,
      passwordHash: payload.passwordHash,
      studentId: String(payload.studentId || "").trim(),
      major: String(payload.major || "Sinh vien TDMU").trim(),
      avatar: initials(payload.name),
      role: "student",
      rating: 5,
      reviewCount: 0,
      phone: "",
      location: "TDMU",
      bio: "",
      createdAt: new Date().toISOString()
    };
    db.users.push(user);
    addNotification(
      db,
      user.id,
      "account",
      "Chao mung den TDMU Market",
      "Tai khoan sinh vien cua ban da duoc kich hoat.",
      "profile"
    );
    await writeDb(db);
    const token = signToken({ id: user.id, role: user.role, createdAt: Date.now() });
    return send(res, 201, { token, user: publicUser(user) });
  }

  if (method === "POST" && pathname === "/api/auth/forgot/request-code") {
    const body = await parseBody(req);
    const email = normalizeEmail(body.email);
    const user = db.users.find(item => item.email.toLowerCase() === email);
    if (!email) return sendError(res, 400, "Vui long nhap email");
    if (!user) return sendError(res, 404, "Khong tim thay tai khoan voi email nay");
    if (!requireAuthCodeDelivery(res)) return;

    const code = createAuthCode(db, email, "forgot");
    await writeDb(db);
    return sendAuthCodeResponse(res, email, "forgot", code);
  }

  if (method === "POST" && pathname === "/api/auth/forgot/reset") {
    const body = await parseBody(req);
    const email = normalizeEmail(body.email);
    const password = String(body.password || "");
    const user = db.users.find(item => item.email.toLowerCase() === email);
    if (!email || !body.code || !password) {
      return sendError(res, 400, "Vui long nhap email, ma xac nhan va mat khau moi");
    }
    if (!user) return sendError(res, 404, "Khong tim thay tai khoan voi email nay");
    if (password.length < 6) return sendError(res, 400, "Mat khau can it nhat 6 ky tu");

    const record = consumeAuthCode(db, email, "forgot", body.code);
    if (!record) return sendError(res, 400, "Ma xac nhan khong dung hoac da het han");

    user.passwordHash = hashPassword(password);
    user.updatedAt = new Date().toISOString();
    addNotification(
      db,
      user.id,
      "account",
      "Mat khau da duoc cap nhat",
      "Tai khoan cua ban vua dat lai mat khau thanh cong.",
      "profile"
    );
    await writeDb(db);
    return send(res, 200, { ok: true });
  }

  if (method === "POST" && pathname === "/api/auth/register") {
    const body = await parseBody(req);
    const email = normalizeEmail(body.email);

    if (body.code) {
      if (!email) return sendError(res, 400, "Vui long nhap email");
      if (db.users.some(user => user.email.toLowerCase() === email)) {
        return sendError(res, 409, "Email da ton tai");
      }
      const record = consumeAuthCode(db, email, "register", body.code);
      if (!record) return sendError(res, 400, "Ma xac nhan khong dung hoac da het han");

      const payload = record.payload || {};
      if (!payload.passwordHash) return sendError(res, 400, "Thong tin dang ky khong hop le");
      const user = {
        id: id("u"),
        name: String(payload.name || "Sinh vien TDMU").trim(),
        email,
        passwordHash: payload.passwordHash,
        studentId: String(payload.studentId || "").trim(),
        major: String(payload.major || "Sinh vien TDMU").trim(),
        avatar: initials(payload.name),
        role: "student",
        rating: 5,
        reviewCount: 0,
        phone: "",
        location: "TDMU",
        bio: "",
        createdAt: new Date().toISOString()
      };
      db.users.push(user);
      addNotification(
        db,
        user.id,
        "account",
        "Chao mung den TDMU Market",
        "Tai khoan sinh vien cua ban da duoc kich hoat.",
        "profile"
      );
      await writeDb(db);
      const token = signToken({ id: user.id, role: user.role, createdAt: Date.now() });
      return send(res, 201, { token, user: publicUser(user) });
    }

    const name = String(body.name || "").trim();
    const studentId = String(body.studentId || "").trim();
    const major = String(body.major || "Sinh vien TDMU").trim();
    const password = String(body.password || "");
    if (!name || !email || !password || !studentId) {
      return sendError(res, 400, "Vui long nhap du thong tin");
    }
    if (!isStudentEmail(email)) {
      return sendError(res, 400, `Chi chap nhan email ${STUDENT_EMAIL_DOMAIN}`);
    }
    if (password.length < 6) {
      return sendError(res, 400, "Mat khau can it nhat 6 ky tu");
    }
    if (db.users.some(user => user.email.toLowerCase() === email)) {
      return sendError(res, 409, "Email da ton tai");
    }
    if (!requireAuthCodeDelivery(res)) return;
    const code = createAuthCode(db, email, "register", {
      name,
      studentId,
      major,
      passwordHash: hashPassword(password)
    });
    await writeDb(db);
    return sendAuthCodeResponse(res, email, "register", code);
  }

  if (method === "GET" && pathname === "/api/me") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    return send(res, 200, { user: publicUser(user) });
  }

  if (method === "PATCH" && pathname === "/api/me") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const body = await parseBody(req);
    const name = String(body.name || "").trim();
    const studentId = String(body.studentId || "").trim();
    const major = String(body.major || "").trim();
    const phone = String(body.phone || "").trim();
    const bio = String(body.bio || "").trim();
    const location = String(body.location || "").trim();
    const avatarImage = String(body.avatarImage || "").trim();

    if (!name || !studentId || !major) {
      return sendError(res, 400, "Vui long nhap ho ten, ma sinh vien va nganh hoc");
    }
    if (avatarImage && !avatarImage.startsWith("data:image/") && !/^https?:\/\//i.test(avatarImage)) {
      return sendError(res, 400, "Anh dai dien khong hop le");
    }

    user.name = name;
    user.studentId = studentId;
    user.major = major;
    user.phone = phone;
    user.bio = bio;
    user.location = location;
    user.avatar = initials(name);
    if (avatarImage) user.avatarImage = avatarImage;
    if (body.avatarImage === "") delete user.avatarImage;
    user.updatedAt = new Date().toISOString();

    await writeDb(db);
    return send(res, 200, { user: publicUser(user) });
  }

  if (method === "GET" && pathname === "/api/notifications") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const notifications = (db.notifications || [])
      .filter(item => item.userId === user.id)
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    return send(res, 200, {
      notifications,
      unread: notifications.filter(item => !item.read).length
    });
  }

  if (method === "PATCH" && pathname === "/api/notifications/read") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    for (const item of db.notifications || []) {
      if (item.userId === user.id) item.read = true;
    }
    await writeDb(db);
    return send(res, 200, { ok: true });
  }

  if (method === "POST" && pathname === "/api/uploads") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const body = await parseBody(req);
    const dataUrl = String(body.dataUrl || "");
    const match = dataUrl.match(/^data:(image\/(?:png|jpeg|jpg|webp));base64,(.+)$/);
    if (!match) return sendError(res, 400, "Anh tai len khong hop le");
    const ext = match[1].includes("png") ? "png" : match[1].includes("webp") ? "webp" : "jpg";
    const buffer = Buffer.from(match[2], "base64");
    if (!buffer.length || buffer.length > 4_000_000) {
      return sendError(res, 400, "Anh phai nho hon 4MB");
    }
    ensureUploadDir();
    const fileName = `${id("img")}.${ext}`;
    fs.writeFileSync(path.join(UPLOAD_DIR, fileName), buffer);
    const imageUrl = `http://${req.headers.host}/uploads/${fileName}`;
    return send(res, 201, { imageUrl });
  }

  if (method === "GET" && pathname === "/api/products") {
    const viewer = getViewer(req, db);
    const q = url.searchParams.get("q") || "";
    const category = url.searchParams.get("category") || "all";
    const mine = url.searchParams.get("mine") === "true";
    let status = url.searchParams.get("status") || "approved";
    if (mine && !viewer) return sendError(res, 401, "Can dang nhap");
    if (!mine && viewer?.role !== "admin") status = "approved";
    const products = db.products
      .filter(product => !mine || product.sellerId === viewer.id)
      .filter(product => status === "all" || product.status === status)
      .filter(product => category === "all" || product.category === category)
      .filter(product => !q || matchesProduct(product, q))
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
      .map(product => enrichProduct(db, product, viewer?.id));
    return send(res, 200, { products });
  }

  if (method === "GET" && pathname === "/api/categories") {
    const categories = [...new Set(db.products.map(product => product.category))];
    return send(res, 200, { categories });
  }

  if (method === "POST" && pathname === "/api/products") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const body = await parseBody(req);
    if (!body.title || !body.description || !body.category || Number(body.price) < 0) {
      return sendError(res, 400, "Thong tin san pham chua hop le");
    }
    const product = {
      id: id("p"),
      sellerId: user.id,
      title: String(body.title).trim(),
      description: String(body.description).trim(),
      category: String(body.category).trim(),
      price: Number(body.price),
      condition: String(body.condition || "Da su dung tot").trim(),
      location: String(body.location || "TDMU").trim(),
      image: String(body.image || "https://images.unsplash.com/photo-1516321318423-f06f85e504b3?auto=format&fit=crop&w=900&q=80").trim(),
      status: "pending",
      saleStatus: "available",
      createdAt: new Date().toISOString()
    };
    db.products.push(product);
    addNotification(
      db,
      user.id,
      "product",
      "Bai dang da duoc gui",
      `San pham "${product.title}" dang cho admin duyet.`,
      "market"
    );
    for (const admin of db.users.filter(item => item.role === "admin")) {
      addNotification(
        db,
        admin.id,
        "moderation",
        "Co bai dang moi",
        `${user.name} vua gui san pham "${product.title}" can duyet.`,
        "admin"
      );
    }
    await writeDb(db);
    return send(res, 201, { product: enrichProduct(db, product, user.id) });
  }

  const productMatch = pathname.match(/^\/api\/products\/([^/]+)$/);
  if (method === "GET" && productMatch) {
    const viewer = getViewer(req, db);
    const product = db.products.find(item => item.id === productMatch[1]);
    if (!product) return sendError(res, 404, "Khong tim thay san pham");
    if (product.status !== "approved" && viewer?.role !== "admin" && viewer?.id !== product.sellerId) {
      return sendError(res, 404, "Khong tim thay san pham");
    }
    return send(res, 200, { product: enrichProduct(db, product, viewer?.id) });
  }

  if ((method === "PATCH" || method === "DELETE") && productMatch) {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const product = db.products.find(item => item.id === productMatch[1]);
    if (!product) return sendError(res, 404, "Khong tim thay san pham");
    if (product.sellerId !== user.id && user.role !== "admin") {
      return sendError(res, 403, "Ban khong co quyen sua bai dang nay");
    }

    if (method === "DELETE") {
      const deleted = removeProduct(db, product.id);
      if (deleted && deleted.sellerId !== user.id) {
        addNotification(db, deleted.sellerId, "moderation", "Bai dang da bi xoa", `San pham "${deleted.title}" da bi admin xoa.`, "profile");
      }
      await writeDb(db);
      return send(res, 200, { ok: true });
    }

    const body = await parseBody(req);
    if (!body.title || !body.description || !body.category || Number(body.price) < 0) {
      return sendError(res, 400, "Thong tin san pham chua hop le");
    }
    product.title = String(body.title).trim();
    product.description = String(body.description).trim();
    product.category = String(body.category).trim();
    product.price = Number(body.price);
    product.condition = String(body.condition || "Da su dung tot").trim();
    product.location = String(body.location || "TDMU").trim();
    product.image = String(body.image || product.image || "").trim();
    product.updatedAt = new Date().toISOString();
    if (user.role !== "admin") {
      product.status = "pending";
      addNotification(db, user.id, "product", "Bai dang da cap nhat", `San pham "${product.title}" dang cho admin duyet lai.`, "profile");
      for (const admin of db.users.filter(item => item.role === "admin")) {
        addNotification(db, admin.id, "moderation", "Bai dang vua duoc sua", `${user.name} da sua "${product.title}" can duyet lai.`, "admin");
      }
    }
    await writeDb(db);
    return send(res, 200, { product: enrichProduct(db, product, user.id) });
  }

  const favoriteMatch = pathname.match(/^\/api\/products\/([^/]+)\/favorite$/);
  if (method === "POST" && favoriteMatch) {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const productId = favoriteMatch[1];
    const index = db.favorites.findIndex(item => item.userId === user.id && item.productId === productId);
    const favorite = index === -1;
    if (favorite) db.favorites.push({ userId: user.id, productId });
    else db.favorites.splice(index, 1);
    const product = db.products.find(item => item.id === productId);
    if (favorite && product && product.sellerId !== user.id) {
      addNotification(
        db,
        product.sellerId,
        "favorite",
        "San pham duoc yeu thich",
        `${user.name} da luu "${product.title}" vao danh sach yeu thich.`,
        "market"
      );
    }
    await writeDb(db);
    return send(res, 200, { favorite });
  }

  if (method === "GET" && pathname === "/api/cart") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const items = db.cartItems
      .filter(item => item.userId === user.id)
      .map(item => {
        const product = db.products.find(product => product.id === item.productId);
        return product ? { ...item, product: enrichProduct(db, product, user.id) } : null;
      })
      .filter(Boolean);
    const total = items.reduce((sum, item) => sum + item.quantity * item.product.price, 0);
    return send(res, 200, { items, total });
  }

  if (method === "POST" && pathname === "/api/cart") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const body = await parseBody(req);
    const product = db.products.find(item => item.id === body.productId && item.status === "approved");
    if (!product) return sendError(res, 404, "Khong tim thay san pham");
    if (product.sellerId === user.id) return sendError(res, 400, "Khong the them bai dang cua chinh ban vao gio");
    const quantity = Math.max(1, Math.min(99, Number(body.quantity || 1)));
    let item = db.cartItems.find(item => item.userId === user.id && item.productId === product.id);
    if (item) {
      item.quantity = Math.min(99, item.quantity + quantity);
      item.updatedAt = new Date().toISOString();
    } else {
      item = {
        id: id("cart"),
        userId: user.id,
        productId: product.id,
        quantity,
        createdAt: new Date().toISOString()
      };
      db.cartItems.push(item);
    }
    await writeDb(db);
    return send(res, 201, { item });
  }

  const cartItemMatch = pathname.match(/^\/api\/cart\/([^/]+)$/);
  if ((method === "PATCH" || method === "DELETE") && cartItemMatch) {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const productId = cartItemMatch[1];
    const index = db.cartItems.findIndex(item => item.userId === user.id && item.productId === productId);
    if (index === -1) return sendError(res, 404, "San pham khong co trong gio hang");
    if (method === "DELETE") {
      db.cartItems.splice(index, 1);
    } else {
      const body = await parseBody(req);
      const quantity = Math.max(1, Math.min(99, Number(body.quantity || 1)));
      db.cartItems[index].quantity = quantity;
      db.cartItems[index].updatedAt = new Date().toISOString();
    }
    await writeDb(db);
    return send(res, 200, { ok: true });
  }

  if (method === "POST" && pathname === "/api/payments/checkout") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const body = await parseBody(req);
    const items = db.cartItems
      .filter(item => item.userId === user.id)
      .map(item => {
        const product = db.products.find(product => product.id === item.productId && product.status === "approved");
        return product ? { product, quantity: item.quantity } : null;
      })
      .filter(Boolean);
    if (!items.length) return sendError(res, 400, "Gio hang dang trong");
    const total = items.reduce((sum, item) => sum + item.quantity * item.product.price, 0);
    const order = {
      id: id("o"),
      userId: user.id,
      method: String(body.method || "banking"),
      status: "paid",
      total,
      items: items.map(item => ({
        productId: item.product.id,
        sellerId: item.product.sellerId,
        title: item.product.title,
        price: item.product.price,
        quantity: item.quantity
      })),
      createdAt: new Date().toISOString()
    };
    db.orders.unshift(order);
    db.cartItems = db.cartItems.filter(item => item.userId !== user.id);
    for (const item of items) {
      addNotification(
        db,
        item.product.sellerId,
        "order",
        "Co don hang moi",
        `${user.name} da thanh toan "${item.product.title}".`,
        "chat"
      );
    }
    addNotification(db, user.id, "order", "Thanh toan thanh cong", `Don hang ${order.id} da duoc ghi nhan.`, "profile");
    await writeDb(db);
    return send(res, 201, { order });
  }

  if (method === "GET" && pathname === "/api/chats") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const chats = db.chats
      .filter(chat => chat.buyerId === user.id || chat.sellerId === user.id)
      .map(chat => {
        const product = db.products.find(item => item.id === chat.productId);
        const otherId = otherParticipantId(chat, user.id);
        const other = db.users.find(item => item.id === otherId);
        const lastMessage = db.messages.filter(message => message.chatId === chat.id).at(-1);
        const unreadCount = unreadMessagesForChat(db, chat, user.id);
        return { ...chat, product, other: publicUser(other), lastMessage, unreadCount };
      })
      .sort((a, b) => new Date(b.lastMessage?.createdAt || b.createdAt) - new Date(a.lastMessage?.createdAt || a.createdAt));
    return send(res, 200, { chats });
  }

  if (method === "POST" && pathname === "/api/chats") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const body = await parseBody(req);
    const product = db.products.find(item => item.id === body.productId);
    if (!product) return sendError(res, 404, "Khong tim thay san pham");
    if (product.sellerId === user.id) return sendError(res, 400, "Ban khong the chat voi chinh minh");
    let chat = db.chats.find(item => item.productId === product.id && item.buyerId === user.id && item.sellerId === product.sellerId);
    if (!chat) {
      chat = {
        id: id("c"),
        productId: product.id,
        buyerId: user.id,
        sellerId: product.sellerId,
        readBy: { [user.id]: new Date().toISOString() },
        createdAt: new Date().toISOString()
      };
      db.chats.push(chat);
      await writeDb(db);
    }
    return send(res, 200, { chat });
  }

  const chatMessagesMatch = pathname.match(/^\/api\/chats\/([^/]+)\/messages$/);
  if (method === "GET" && chatMessagesMatch) {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const chat = db.chats.find(item => item.id === chatMessagesMatch[1]);
    if (!chat || (chat.buyerId !== user.id && chat.sellerId !== user.id)) {
      return sendError(res, 404, "Khong tim thay cuoc tro chuyen");
    }
    const messages = db.messages.filter(message => message.chatId === chat.id);
    markChatPairRead(db, chat, user);
    await writeDb(db);
    return send(res, 200, { messages });
  }

  if (method === "POST" && chatMessagesMatch) {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const chat = db.chats.find(item => item.id === chatMessagesMatch[1]);
    if (!chat || (chat.buyerId !== user.id && chat.sellerId !== user.id)) {
      return sendError(res, 404, "Khong tim thay cuoc tro chuyen");
    }
    const body = await parseBody(req);
    const text = String(body.text || "").trim();
    const imageUrl = String(body.imageUrl || "").trim();
    if (!text && !imageUrl) return sendError(res, 400, "Tin nhan khong duoc de trong");
    if (imageUrl && !/^https?:\/\//i.test(imageUrl) && !imageUrl.startsWith("/uploads/")) {
      return sendError(res, 400, "Anh chat khong hop le");
    }
    const message = {
      id: id("m"),
      chatId: chat.id,
      senderId: user.id,
      text,
      imageUrl,
      type: imageUrl ? "image" : "text",
      createdAt: new Date().toISOString()
    };
    db.messages.push(message);
    chat.readBy ||= {};
    chat.readBy[user.id] = message.createdAt;
    const receiverId = otherParticipantId(chat, user.id);
    const preview = text || "Da gui mot anh";
    addNotification(
      db,
      receiverId,
      "chat",
      "Tin nhan moi",
      `${user.name}: ${preview.slice(0, 90)}`,
      "chat",
      { chatId: chat.id, senderId: user.id }
    );
    await writeDb(db);
    emitChat(chat.id, "message", message);
    return send(res, 201, { message });
  }

  if (method === "PATCH" && chatMessagesMatch) {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const chat = db.chats.find(item => item.id === chatMessagesMatch[1]);
    if (!chat || (chat.buyerId !== user.id && chat.sellerId !== user.id)) {
      return sendError(res, 404, "Khong tim thay cuoc tro chuyen");
    }
    markChatPairRead(db, chat, user);
    await writeDb(db);
    return send(res, 200, { ok: true });
  }

  const chatStreamMatch = pathname.match(/^\/api\/chats\/([^/]+)\/stream$/);
  if (method === "GET" && chatStreamMatch) {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const chat = db.chats.find(item => item.id === chatStreamMatch[1]);
    if (!chat || (chat.buyerId !== user.id && chat.sellerId !== user.id)) {
      return sendError(res, 404, "Khong tim thay cuoc tro chuyen");
    }
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive"
    });
    res.write("event: ready\ndata: {}\n\n");
    if (!clients.has(chat.id)) clients.set(chat.id, new Set());
    clients.get(chat.id).add(res);
    req.on("close", () => {
      clients.get(chat.id)?.delete(res);
    });
    return;
  }

  if (method === "POST" && pathname === "/api/reviews") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    const body = await parseBody(req);
    const seller = db.users.find(item => item.id === body.sellerId);
    const rating = Number(body.rating);
    if (!seller || seller.id === user.id || rating < 1 || rating > 5) {
      return sendError(res, 400, "Danh gia khong hop le");
    }
    const review = {
      id: id("r"),
      sellerId: seller.id,
      buyerId: user.id,
      rating,
      comment: String(body.comment || "").trim(),
      createdAt: new Date().toISOString()
    };
    db.reviews.push(review);
    const sellerReviews = db.reviews.filter(item => item.sellerId === seller.id);
    seller.rating = Math.round((sellerReviews.reduce((sum, item) => sum + Number(item.rating), 0) / sellerReviews.length) * 10) / 10;
    seller.reviewCount = sellerReviews.length;
    addNotification(
      db,
      seller.id,
      "review",
      "Danh gia moi",
      `${user.name} vua danh gia ban ${rating} sao.`,
      "market"
    );
    await writeDb(db);
    return send(res, 201, { review, seller: publicUser(seller) });
  }

  if (method === "GET" && pathname === "/api/admin/stats") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    if (user.role !== "admin") return sendError(res, 403, "Chi admin moi duoc truy cap");
    return send(res, 200, {
      stats: {
        users: db.users.length,
        blockedUsers: db.users.filter(user => user.status === "blocked").length,
        products: db.products.length,
        pending: db.products.filter(product => product.status === "pending").length,
        approved: db.products.filter(product => product.status === "approved").length,
        hidden: db.products.filter(product => product.status === "hidden").length,
        chats: db.chats.length,
        reviews: db.reviews.length,
        orders: db.orders.length,
        revenue: db.orders.reduce((sum, order) => sum + Number(order.total || 0), 0)
      }
    });
  }

  const adminDetailMatch = pathname.match(/^\/api\/admin\/details\/([^/]+)$/);
  if (method === "GET" && adminDetailMatch) {
    const user = requireAuth(req, res, db);
    if (!user) return;
    if (user.role !== "admin") return sendError(res, 403, "Chi admin moi duoc truy cap");

    const type = adminDetailMatch[1];
    const adminUsers = () => db.users
      .map(item => ({
        ...publicUser(item),
        status: item.status || "active",
        productCount: db.products.filter(product => product.sellerId === item.id).length,
        pendingCount: db.products.filter(product => product.sellerId === item.id && product.status === "pending").length,
        orderCount: db.orders.filter(order => order.userId === item.id).length
      }))
      .sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
    const adminProducts = status => db.products
      .filter(product => status === "all" || product.status === status)
      .sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0))
      .map(product => enrichProduct(db, product, user.id));
    const orders = () => db.orders
      .map(order => ({
        ...order,
        buyer: publicUser(db.users.find(item => item.id === order.userId)),
        itemCount: (order.items || []).reduce((sum, item) => sum + Number(item.quantity || 0), 0)
      }))
      .sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
    const chats = () => db.chats
      .map(chat => {
        const messages = db.messages.filter(message => message.chatId === chat.id);
        return {
          ...chat,
          buyer: publicUser(db.users.find(item => item.id === chat.buyerId)),
          seller: publicUser(db.users.find(item => item.id === chat.sellerId)),
          product: db.products.find(item => item.id === chat.productId),
          lastMessage: messages.at(-1),
          messageCount: messages.length
        };
      })
      .sort((a, b) => new Date(b.lastMessage?.createdAt || b.createdAt || 0) - new Date(a.lastMessage?.createdAt || a.createdAt || 0));
    const reviews = () => db.reviews
      .map(review => ({
        ...review,
        buyer: publicUser(db.users.find(item => item.id === review.buyerId)),
        seller: publicUser(db.users.find(item => item.id === review.sellerId))
      }))
      .sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));

    const detail = {
      users: { title: "Nguoi dung", items: adminUsers() },
      blockedUsers: { title: "Tai khoan dang khoa", items: adminUsers().filter(item => item.status === "blocked") },
      products: { title: "Tat ca san pham", items: adminProducts("all") },
      pending: { title: "Bai dang cho duyet", items: adminProducts("pending") },
      approved: { title: "Bai dang da duyet", items: adminProducts("approved") },
      hidden: { title: "Bai dang da an", items: adminProducts("hidden") },
      orders: { title: "Don hang", items: orders() },
      revenue: { title: "Doanh thu", items: orders() },
      chats: { title: "Cuoc tro chuyen", items: chats() },
      reviews: { title: "Danh gia", items: reviews() }
    }[type];

    if (!detail) return sendError(res, 404, "Khong tim thay chi tiet thong ke");
    return send(res, 200, { type, title: detail.title, count: detail.items.length, items: detail.items });
  }

  if (method === "GET" && pathname === "/api/admin/users") {
    const user = requireAuth(req, res, db);
    if (!user) return;
    if (user.role !== "admin") return sendError(res, 403, "Chi admin moi duoc truy cap");
    const users = db.users
      .map(item => ({
        ...publicUser(item),
        status: item.status || "active",
        productCount: db.products.filter(product => product.sellerId === item.id).length,
        pendingCount: db.products.filter(product => product.sellerId === item.id && product.status === "pending").length,
        orderCount: db.orders.filter(order => order.userId === item.id).length
      }))
      .sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
    return send(res, 200, { users });
  }

  const adminUserMatch = pathname.match(/^\/api\/admin\/users\/([^/]+)$/);
  if ((method === "PATCH" || method === "DELETE") && adminUserMatch) {
    const user = requireAuth(req, res, db);
    if (!user) return;
    if (user.role !== "admin") return sendError(res, 403, "Chi admin moi duoc thuc hien");
    const target = db.users.find(item => item.id === adminUserMatch[1]);
    if (!target) return sendError(res, 404, "Khong tim thay tai khoan");
    if (target.id === user.id) return sendError(res, 400, "Khong the thao tac voi tai khoan dang dang nhap");
    if (target.role === "admin") return sendError(res, 400, "Khong the thao tac voi tai khoan admin khac");

    if (method === "DELETE") {
      removeUser(db, target.id);
      await writeDb(db);
      return send(res, 200, { ok: true });
    }

    const body = await parseBody(req);
    if (!["active", "blocked"].includes(body.status)) {
      return sendError(res, 400, "Trang thai tai khoan khong hop le");
    }
    target.status = body.status;
    target.updatedAt = new Date().toISOString();
    addNotification(
      db,
      target.id,
      "account",
      body.status === "blocked" ? "Tai khoan da bi khoa" : "Tai khoan da duoc mo khoa",
      body.status === "blocked"
        ? "Admin da tam khoa tai khoan cua ban."
        : "Admin da mo khoa tai khoan cua ban.",
      "profile"
    );
    await writeDb(db);
    return send(res, 200, { user: publicUser(target) });
  }

  const moderateMatch = pathname.match(/^\/api\/admin\/products\/([^/]+)$/);
  if ((method === "PATCH" || method === "DELETE") && moderateMatch) {
    const user = requireAuth(req, res, db);
    if (!user) return;
    if (user.role !== "admin") return sendError(res, 403, "Chi admin moi duoc thuc hien");
    const product = db.products.find(item => item.id === moderateMatch[1]);
    if (!product) return sendError(res, 404, "Khong tim thay san pham");
    if (method === "DELETE") {
      const deleted = removeProduct(db, product.id);
      addNotification(
        db,
        deleted.sellerId,
        "moderation",
        "Bai dang da bi xoa",
        `San pham "${deleted.title}" da bi admin xoa.`,
        "profile"
      );
      await writeDb(db);
      return send(res, 200, { ok: true });
    } else {
      const body = await parseBody(req);
      if (!["approved", "pending", "hidden"].includes(body.status)) {
        return sendError(res, 400, "Trang thai khong hop le");
      }
      product.status = body.status;
    }
    addNotification(
      db,
      product.sellerId,
      "moderation",
      product.status === "approved" ? "Bai dang da duoc duyet" : "Bai dang da duoc cap nhat",
      `San pham "${product.title}" hien co trang thai ${product.status}.`,
      "market"
    );
    await writeDb(db);
    return send(res, 200, { product: enrichProduct(db, product, user.id) });
  }

  sendError(res, 404, "API khong ton tai");
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  try {
    if (url.pathname.startsWith("/api/")) {
      await handleApi(req, res, url);
    } else {
      serveStatic(req, res, url.pathname);
    }
  } catch (error) {
    sendError(res, 500, error.message || "Loi server");
  }
});

server.listen(PORT, () => {
  console.log("TDMU Marketplace dang chay");
});
