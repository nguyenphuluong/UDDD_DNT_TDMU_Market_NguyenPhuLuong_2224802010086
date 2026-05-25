const STORAGE_DRIVER = String(process.env.DB_CLIENT || process.env.DB_TYPE || "json").trim().toLowerCase();

const SQLSERVER_DATABASE = process.env.SQLSERVER_DATABASE || process.env.DB_NAME || "tdmu_market";
const SQLSERVER_SCHEMA = process.env.SQLSERVER_SCHEMA || "dbo";
const SQLSERVER_TRUSTED = sqlBool(process.env.SQLSERVER_TRUSTED_CONNECTION, false);

const COLLECTIONS = [
  "users",
  "products",
  "favorites",
  "chats",
  "messages",
  "reviews",
  "notifications",
  "cartItems",
  "orders",
  "authCodes"
];

let sqlServer = null;
let sqlServerPoolPromise = null;
let sqlServerSchemaReady = false;

function emptyDb() {
  return Object.fromEntries(COLLECTIONS.map(collection => [collection, []]));
}

function normalizeDb(db = {}) {
  const normalized = emptyDb();
  for (const collection of COLLECTIONS) {
    normalized[collection] = Array.isArray(db[collection]) ? db[collection] : [];
  }
  return normalized;
}

function sqlBool(value, fallback) {
  if (value === undefined || value === null || value === "") return fallback;
  return ["1", "true", "yes", "on"].includes(String(value).toLowerCase());
}

function sqlIdentifier(value) {
  const name = String(value || "").trim();
  if (!/^[A-Za-z0-9_]+$/.test(name)) {
    throw new Error(`Ten SQL Server khong hop le: ${name}`);
  }
  return `[${name}]`;
}

function sqlTable(table) {
  return `${sqlIdentifier(SQLSERVER_SCHEMA)}.${sqlIdentifier(table)}`;
}

function sqlObjectName(table) {
  return `${SQLSERVER_SCHEMA}.${table}`.replace(/'/g, "''");
}

function parseSqlServerName(value) {
  const raw = String(value || ".\\SQLEXPRESS").trim();
  const [hostPart, instanceName] = raw.includes("\\") ? raw.split("\\") : [raw, ""];
  return {
    host: hostPart === "." ? "localhost" : hostPart,
    instanceName
  };
}

function baseSqlServerConfig(database) {
  const { host, instanceName } = parseSqlServerName(
    process.env.SQLSERVER_SERVER || process.env.DB_HOST || ".\\SQLEXPRESS"
  );
  const portValue = process.env.SQLSERVER_PORT || process.env.DB_PORT || "";
  const config = {
    server: host,
    database,
    user: process.env.SQLSERVER_USER || process.env.DB_USER || "tdmu_app",
    password: process.env.SQLSERVER_PASSWORD || process.env.DB_PASSWORD || "",
    pool: {
      max: Number(process.env.SQLSERVER_POOL_MAX || 10),
      min: 0,
      idleTimeoutMillis: 30000
    },
    options: {
      encrypt: sqlBool(process.env.SQLSERVER_ENCRYPT, false),
      trustServerCertificate: sqlBool(process.env.SQLSERVER_TRUST_SERVER_CERTIFICATE, true)
    }
  };

  if (portValue) {
    config.port = Number(portValue);
  } else if (instanceName) {
    config.options.instanceName = instanceName;
  }

  return config;
}

function sqlServerConnectionString(database) {
  const server = process.env.SQLSERVER_SERVER || process.env.DB_HOST || ".\\SQLEXPRESS";
  const port = process.env.SQLSERVER_PORT || process.env.DB_PORT || "";
  const driver = process.env.SQLSERVER_ODBC_DRIVER || "ODBC Driver 18 for SQL Server";
  const serverPart = port ? `tcp:${server},${port}` : server;
  const encrypt = sqlBool(process.env.SQLSERVER_ENCRYPT, false) ? "yes" : "no";
  const trustCert = sqlBool(process.env.SQLSERVER_TRUST_SERVER_CERTIFICATE, true) ? "yes" : "no";
  return [
    `Driver={${driver}}`,
    `Server=${serverPart}`,
    `Database=${database}`,
    "Trusted_Connection=Yes",
    `Encrypt=${encrypt}`,
    `TrustServerCertificate=${trustCert}`
  ].join(";");
}

function getSqlServerModule() {
  if (sqlServer) return sqlServer;
  try {
    sqlServer = SQLSERVER_TRUSTED ? require("mssql/msnodesqlv8") : require("mssql");
    return sqlServer;
  } catch {
    throw new Error("Chua cai package SQL Server. Hay chay: npm install");
  }
}

async function ensureSqlServerDatabase() {
  const sql = getSqlServerModule();
  const masterPool = new sql.ConnectionPool(
    SQLSERVER_TRUSTED
      ? { connectionString: sqlServerConnectionString("master") }
      : baseSqlServerConfig("master")
  );
  await masterPool.connect();
  try {
    await masterPool.request().query(`
      IF DB_ID(N'${SQLSERVER_DATABASE.replace(/'/g, "''")}') IS NULL
      BEGIN
        CREATE DATABASE ${sqlIdentifier(SQLSERVER_DATABASE)};
      END
    `);
  } finally {
    await masterPool.close();
  }
}

async function getSqlServerPool() {
  if (!sqlServerPoolPromise) {
    sqlServerPoolPromise = (async () => {
      await ensureSqlServerDatabase();
      const sql = getSqlServerModule();
      const pool = new sql.ConnectionPool(
        SQLSERVER_TRUSTED
          ? { connectionString: sqlServerConnectionString(SQLSERVER_DATABASE) }
          : baseSqlServerConfig(SQLSERVER_DATABASE)
      );
      await pool.connect();
      return pool;
    })();
  }
  return sqlServerPoolPromise;
}

async function ensureSqlServerSchema() {
  if (sqlServerSchemaReady) return;
  const pool = await getSqlServerPool();
  await pool.request().query(sqlServerSchemaSql());
  sqlServerSchemaReady = true;
}

function sqlServerSchemaSql() {
  const users = sqlTable("Users");
  const products = sqlTable("Products");
  const favorites = sqlTable("Favorites");
  const chats = sqlTable("Chats");
  const messages = sqlTable("Messages");
  const reviews = sqlTable("Reviews");
  const notifications = sqlTable("Notifications");
  const cartItems = sqlTable("CartItems");
  const orders = sqlTable("Orders");
  const orderItems = sqlTable("OrderItems");
  const authCodes = sqlTable("AuthCodes");

  return `
    IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'${SQLSERVER_SCHEMA.replace(/'/g, "''")}')
    BEGIN
      EXEC(N'CREATE SCHEMA ${SQLSERVER_SCHEMA.replace(/'/g, "''")}')
    END;

    IF OBJECT_ID(N'${sqlObjectName("app_documents")}', N'U') IS NOT NULL
      DROP TABLE ${sqlTable("app_documents")};

    IF OBJECT_ID(N'${sqlObjectName("Users")}', N'U') IS NULL
    BEGIN
      CREATE TABLE ${users} (
        id NVARCHAR(80) NOT NULL CONSTRAINT PK_Users PRIMARY KEY,
        name NVARCHAR(160) NOT NULL,
        email NVARCHAR(255) NOT NULL CONSTRAINT UQ_Users_email UNIQUE,
        password_hash NVARCHAR(160) NOT NULL,
        student_id NVARCHAR(80) NOT NULL,
        major NVARCHAR(160) NOT NULL,
        avatar NVARCHAR(16) NULL,
        avatar_image NVARCHAR(MAX) NULL,
        role NVARCHAR(32) NOT NULL,
        status NVARCHAR(32) NULL,
        rating DECIMAL(4, 2) NOT NULL CONSTRAINT DF_Users_rating DEFAULT 5,
        review_count INT NOT NULL CONSTRAINT DF_Users_review_count DEFAULT 0,
        phone NVARCHAR(40) NULL,
        location NVARCHAR(255) NULL,
        bio NVARCHAR(MAX) NULL,
        created_at DATETIME2 NULL,
        updated_at DATETIME2 NULL
      );
    END;

    IF OBJECT_ID(N'${sqlObjectName("Products")}', N'U') IS NULL
    BEGIN
      CREATE TABLE ${products} (
        id NVARCHAR(80) NOT NULL CONSTRAINT PK_Products PRIMARY KEY,
        seller_id NVARCHAR(80) NOT NULL,
        title NVARCHAR(255) NOT NULL,
        description NVARCHAR(MAX) NOT NULL,
        category NVARCHAR(160) NOT NULL,
        price DECIMAL(18, 2) NOT NULL,
        condition NVARCHAR(160) NULL,
        location NVARCHAR(255) NULL,
        image NVARCHAR(MAX) NULL,
        status NVARCHAR(32) NOT NULL,
        sale_status NVARCHAR(32) NULL,
        created_at DATETIME2 NULL,
        updated_at DATETIME2 NULL,
        CONSTRAINT FK_Products_Users FOREIGN KEY (seller_id) REFERENCES ${users}(id)
      );
    END;

    IF OBJECT_ID(N'${sqlObjectName("Favorites")}', N'U') IS NULL
    BEGIN
      CREATE TABLE ${favorites} (
        user_id NVARCHAR(80) NOT NULL,
        product_id NVARCHAR(80) NOT NULL,
        CONSTRAINT PK_Favorites PRIMARY KEY (user_id, product_id),
        CONSTRAINT FK_Favorites_Users FOREIGN KEY (user_id) REFERENCES ${users}(id),
        CONSTRAINT FK_Favorites_Products FOREIGN KEY (product_id) REFERENCES ${products}(id)
      );
    END;

    IF OBJECT_ID(N'${sqlObjectName("Chats")}', N'U') IS NULL
    BEGIN
      CREATE TABLE ${chats} (
        id NVARCHAR(80) NOT NULL CONSTRAINT PK_Chats PRIMARY KEY,
        product_id NVARCHAR(80) NOT NULL,
        buyer_id NVARCHAR(80) NOT NULL,
        seller_id NVARCHAR(80) NOT NULL,
        read_by_json NVARCHAR(MAX) NULL,
        created_at DATETIME2 NULL,
        CONSTRAINT FK_Chats_Products FOREIGN KEY (product_id) REFERENCES ${products}(id),
        CONSTRAINT FK_Chats_Buyer FOREIGN KEY (buyer_id) REFERENCES ${users}(id),
        CONSTRAINT FK_Chats_Seller FOREIGN KEY (seller_id) REFERENCES ${users}(id),
        CONSTRAINT CK_Chats_read_by_json CHECK (read_by_json IS NULL OR ISJSON(read_by_json) = 1)
      );
    END;

    IF OBJECT_ID(N'${sqlObjectName("Messages")}', N'U') IS NULL
    BEGIN
      CREATE TABLE ${messages} (
        id NVARCHAR(80) NOT NULL CONSTRAINT PK_Messages PRIMARY KEY,
        chat_id NVARCHAR(80) NOT NULL,
        sender_id NVARCHAR(80) NOT NULL,
        text NVARCHAR(MAX) NULL,
        image_url NVARCHAR(MAX) NULL,
        type NVARCHAR(32) NULL,
        created_at DATETIME2 NULL,
        CONSTRAINT FK_Messages_Chats FOREIGN KEY (chat_id) REFERENCES ${chats}(id),
        CONSTRAINT FK_Messages_Users FOREIGN KEY (sender_id) REFERENCES ${users}(id)
      );
    END;

    IF OBJECT_ID(N'${sqlObjectName("Reviews")}', N'U') IS NULL
    BEGIN
      CREATE TABLE ${reviews} (
        id NVARCHAR(80) NOT NULL CONSTRAINT PK_Reviews PRIMARY KEY,
        seller_id NVARCHAR(80) NOT NULL,
        buyer_id NVARCHAR(80) NOT NULL,
        rating INT NOT NULL,
        comment NVARCHAR(MAX) NULL,
        created_at DATETIME2 NULL,
        CONSTRAINT FK_Reviews_Seller FOREIGN KEY (seller_id) REFERENCES ${users}(id),
        CONSTRAINT FK_Reviews_Buyer FOREIGN KEY (buyer_id) REFERENCES ${users}(id)
      );
    END;

    IF OBJECT_ID(N'${sqlObjectName("Notifications")}', N'U') IS NULL
    BEGIN
      CREATE TABLE ${notifications} (
        id NVARCHAR(80) NOT NULL CONSTRAINT PK_Notifications PRIMARY KEY,
        user_id NVARCHAR(80) NOT NULL,
        type NVARCHAR(64) NULL,
        title NVARCHAR(255) NOT NULL,
        message NVARCHAR(MAX) NOT NULL,
        link NVARCHAR(80) NULL,
        is_read BIT NOT NULL CONSTRAINT DF_Notifications_is_read DEFAULT 0,
        chat_id NVARCHAR(80) NULL,
        sender_id NVARCHAR(80) NULL,
        extra_json NVARCHAR(MAX) NULL,
        created_at DATETIME2 NULL,
        CONSTRAINT FK_Notifications_Users FOREIGN KEY (user_id) REFERENCES ${users}(id),
        CONSTRAINT CK_Notifications_extra_json CHECK (extra_json IS NULL OR ISJSON(extra_json) = 1)
      );
    END;

    IF OBJECT_ID(N'${sqlObjectName("CartItems")}', N'U') IS NULL
    BEGIN
      CREATE TABLE ${cartItems} (
        id NVARCHAR(80) NOT NULL CONSTRAINT PK_CartItems PRIMARY KEY,
        user_id NVARCHAR(80) NOT NULL,
        product_id NVARCHAR(80) NOT NULL,
        quantity INT NOT NULL,
        created_at DATETIME2 NULL,
        updated_at DATETIME2 NULL,
        CONSTRAINT UQ_CartItems_user_product UNIQUE (user_id, product_id),
        CONSTRAINT FK_CartItems_Users FOREIGN KEY (user_id) REFERENCES ${users}(id),
        CONSTRAINT FK_CartItems_Products FOREIGN KEY (product_id) REFERENCES ${products}(id)
      );
    END;

    IF OBJECT_ID(N'${sqlObjectName("Orders")}', N'U') IS NULL
    BEGIN
      CREATE TABLE ${orders} (
        id NVARCHAR(80) NOT NULL CONSTRAINT PK_Orders PRIMARY KEY,
        user_id NVARCHAR(80) NOT NULL,
        method NVARCHAR(64) NULL,
        status NVARCHAR(64) NULL,
        total DECIMAL(18, 2) NOT NULL,
        created_at DATETIME2 NULL,
        CONSTRAINT FK_Orders_Users FOREIGN KEY (user_id) REFERENCES ${users}(id)
      );
    END;

    IF OBJECT_ID(N'${sqlObjectName("OrderItems")}', N'U') IS NULL
    BEGIN
      CREATE TABLE ${orderItems} (
        order_id NVARCHAR(80) NOT NULL,
        line_index INT NOT NULL,
        product_id NVARCHAR(80) NOT NULL,
        seller_id NVARCHAR(80) NOT NULL,
        title NVARCHAR(255) NOT NULL,
        price DECIMAL(18, 2) NOT NULL,
        quantity INT NOT NULL,
        CONSTRAINT PK_OrderItems PRIMARY KEY (order_id, line_index),
        CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (order_id) REFERENCES ${orders}(id),
        CONSTRAINT FK_OrderItems_Products FOREIGN KEY (product_id) REFERENCES ${products}(id),
        CONSTRAINT FK_OrderItems_Seller FOREIGN KEY (seller_id) REFERENCES ${users}(id)
      );
    END;

    IF OBJECT_ID(N'${sqlObjectName("AuthCodes")}', N'U') IS NULL
    BEGIN
      CREATE TABLE ${authCodes} (
        id NVARCHAR(80) NOT NULL CONSTRAINT PK_AuthCodes PRIMARY KEY,
        email NVARCHAR(255) NOT NULL,
        purpose NVARCHAR(64) NOT NULL,
        code NVARCHAR(16) NOT NULL,
        payload_json NVARCHAR(MAX) NULL,
        created_at DATETIME2 NULL,
        expires_at DATETIME2 NULL,
        CONSTRAINT CK_AuthCodes_payload_json CHECK (payload_json IS NULL OR ISJSON(payload_json) = 1)
      );
    END;
  `;
}

function parseJson(value, fallback) {
  if (!value) return fallback;
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

function cleanObject(object) {
  for (const key of Object.keys(object)) {
    if (object[key] === undefined) delete object[key];
  }
  return object;
}

function dateOrNull(value) {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function isoOrUndefined(value) {
  const date = dateOrNull(value);
  return date ? date.toISOString() : undefined;
}

async function queryRows(pool, query) {
  const result = await pool.request().query(query);
  return result.recordset;
}

async function readSqlServerDb() {
  await ensureSqlServerSchema();
  const pool = await getSqlServerPool();

  const users = await queryRows(pool, `SELECT * FROM ${sqlTable("Users")} ORDER BY created_at`);

  const products = await queryRows(pool, `SELECT * FROM ${sqlTable("Products")} ORDER BY created_at`);
  const favorites = await queryRows(pool, `SELECT * FROM ${sqlTable("Favorites")}`);
  const chats = await queryRows(pool, `SELECT * FROM ${sqlTable("Chats")} ORDER BY created_at`);
  const messages = await queryRows(pool, `SELECT * FROM ${sqlTable("Messages")} ORDER BY created_at`);
  const reviews = await queryRows(pool, `SELECT * FROM ${sqlTable("Reviews")} ORDER BY created_at`);
  const notifications = await queryRows(pool, `SELECT * FROM ${sqlTable("Notifications")} ORDER BY created_at`);
  const cartItems = await queryRows(pool, `SELECT * FROM ${sqlTable("CartItems")} ORDER BY created_at`);
  const orders = await queryRows(pool, `SELECT * FROM ${sqlTable("Orders")} ORDER BY created_at`);
  const orderItems = await queryRows(pool, `SELECT * FROM ${sqlTable("OrderItems")} ORDER BY order_id, line_index`);
  const authCodes = await queryRows(pool, `SELECT * FROM ${sqlTable("AuthCodes")} ORDER BY created_at`);

  const db = emptyDb();
  db.users = users.map(row => cleanObject({
    id: row.id,
    name: row.name,
    email: row.email,
    passwordHash: row.password_hash,
    studentId: row.student_id,
    major: row.major,
    avatar: row.avatar,
    avatarImage: row.avatar_image || undefined,
    role: row.role,
    status: row.status || undefined,
    rating: Number(row.rating ?? 5),
    reviewCount: Number(row.review_count ?? 0),
    phone: row.phone || "",
    location: row.location || "",
    bio: row.bio || "",
    createdAt: isoOrUndefined(row.created_at),
    updatedAt: isoOrUndefined(row.updated_at)
  }));
  db.products = products.map(row => cleanObject({
    id: row.id,
    sellerId: row.seller_id,
    title: row.title,
    description: row.description,
    category: row.category,
    price: Number(row.price || 0),
    condition: row.condition || "",
    location: row.location || "",
    image: row.image || "",
    status: row.status,
    saleStatus: row.sale_status || undefined,
    createdAt: isoOrUndefined(row.created_at),
    updatedAt: isoOrUndefined(row.updated_at)
  }));
  db.favorites = favorites.map(row => ({ userId: row.user_id, productId: row.product_id }));
  db.chats = chats.map(row => cleanObject({
    id: row.id,
    productId: row.product_id,
    buyerId: row.buyer_id,
    sellerId: row.seller_id,
    readBy: parseJson(row.read_by_json, {}),
    createdAt: isoOrUndefined(row.created_at)
  }));
  db.messages = messages.map(row => cleanObject({
    id: row.id,
    chatId: row.chat_id,
    senderId: row.sender_id,
    text: row.text || "",
    imageUrl: row.image_url || "",
    type: row.type || "text",
    createdAt: isoOrUndefined(row.created_at)
  }));
  db.reviews = reviews.map(row => cleanObject({
    id: row.id,
    sellerId: row.seller_id,
    buyerId: row.buyer_id,
    rating: Number(row.rating || 0),
    comment: row.comment || "",
    createdAt: isoOrUndefined(row.created_at)
  }));
  db.notifications = notifications.map(row => cleanObject({
    ...parseJson(row.extra_json, {}),
    id: row.id,
    userId: row.user_id,
    type: row.type || "",
    title: row.title,
    message: row.message,
    link: row.link || "notifications",
    read: Boolean(row.is_read),
    chatId: row.chat_id || undefined,
    senderId: row.sender_id || undefined,
    createdAt: isoOrUndefined(row.created_at)
  }));
  db.cartItems = cartItems.map(row => cleanObject({
    id: row.id,
    userId: row.user_id,
    productId: row.product_id,
    quantity: Number(row.quantity || 1),
    createdAt: isoOrUndefined(row.created_at),
    updatedAt: isoOrUndefined(row.updated_at)
  }));

  const orderMap = new Map(orders.map(row => [row.id, cleanObject({
    id: row.id,
    userId: row.user_id,
    method: row.method || "",
    status: row.status || "",
    total: Number(row.total || 0),
    items: [],
    createdAt: isoOrUndefined(row.created_at)
  })]));
  for (const row of orderItems) {
    const order = orderMap.get(row.order_id);
    if (!order) continue;
    order.items.push({
      productId: row.product_id,
      sellerId: row.seller_id,
      title: row.title,
      price: Number(row.price || 0),
      quantity: Number(row.quantity || 1)
    });
  }
  db.orders = [...orderMap.values()];

  db.authCodes = authCodes.map(row => cleanObject({
    id: row.id,
    email: row.email,
    purpose: row.purpose,
    code: row.code,
    payload: parseJson(row.payload_json, {}),
    createdAt: isoOrUndefined(row.created_at),
    expiresAt: isoOrUndefined(row.expires_at)
  }));

  return db;
}

async function writeSqlServerDb(db) {
  await ensureSqlServerSchema();
  const sql = getSqlServerModule();
  const pool = await getSqlServerPool();
  const transaction = new sql.Transaction(pool);
  const normalized = normalizeDb(db);

  await transaction.begin();
  try {
    await deleteSqlServerRows(sql, transaction);
    await insertUsers(sql, transaction, normalized.users);
    await insertProducts(sql, transaction, normalized.products);
    await insertFavorites(sql, transaction, normalized.favorites);
    await insertChats(sql, transaction, normalized.chats);
    await insertMessages(sql, transaction, normalized.messages);
    await insertReviews(sql, transaction, normalized.reviews);
    await insertNotifications(sql, transaction, normalized.notifications);
    await insertCartItems(sql, transaction, normalized.cartItems);
    await insertOrders(sql, transaction, normalized.orders);
    await insertAuthCodes(sql, transaction, normalized.authCodes);
    await transaction.commit();
  } catch (error) {
    await transaction.rollback();
    throw error;
  }
}

async function deleteSqlServerRows(sql, transaction) {
  await new sql.Request(transaction).query(`
    DELETE FROM ${sqlTable("OrderItems")};
    DELETE FROM ${sqlTable("CartItems")};
    DELETE FROM ${sqlTable("Favorites")};
    DELETE FROM ${sqlTable("Reviews")};
    DELETE FROM ${sqlTable("Messages")};
    DELETE FROM ${sqlTable("Notifications")};
    DELETE FROM ${sqlTable("AuthCodes")};
    DELETE FROM ${sqlTable("Chats")};
    DELETE FROM ${sqlTable("Orders")};
    DELETE FROM ${sqlTable("Products")};
    DELETE FROM ${sqlTable("Users")};
  `);
}

async function insertUsers(sql, transaction, users) {
  for (const user of users) {
    await new sql.Request(transaction)
      .input("id", sql.NVarChar(80), user.id)
      .input("name", sql.NVarChar(160), user.name || "Sinh vien TDMU")
      .input("email", sql.NVarChar(255), user.email)
      .input("password_hash", sql.NVarChar(160), user.passwordHash || "")
      .input("student_id", sql.NVarChar(80), user.studentId || "")
      .input("major", sql.NVarChar(160), user.major || "Sinh vien TDMU")
      .input("avatar", sql.NVarChar(16), user.avatar || "")
      .input("avatar_image", sql.NVarChar(sql.MAX), user.avatarImage || null)
      .input("role", sql.NVarChar(32), user.role || "student")
      .input("status", sql.NVarChar(32), user.status || null)
      .input("rating", sql.Decimal(4, 2), Number(user.rating || 5))
      .input("review_count", sql.Int, Number(user.reviewCount || 0))
      .input("phone", sql.NVarChar(40), user.phone || "")
      .input("location", sql.NVarChar(255), user.location || "")
      .input("bio", sql.NVarChar(sql.MAX), user.bio || "")
      .input("created_at", sql.DateTime2, dateOrNull(user.createdAt))
      .input("updated_at", sql.DateTime2, dateOrNull(user.updatedAt))
      .query(`
        INSERT INTO ${sqlTable("Users")} (
          id, name, email, password_hash, student_id, major, avatar, avatar_image,
          role, status, rating, review_count, phone, location, bio, created_at, updated_at
        )
        VALUES (
          @id, @name, @email, @password_hash, @student_id, @major, @avatar, @avatar_image,
          @role, @status, @rating, @review_count, @phone, @location, @bio, @created_at, @updated_at
        )
      `);
  }
}

async function insertProducts(sql, transaction, products) {
  for (const product of products.filter(item => item.sellerId)) {
    await new sql.Request(transaction)
      .input("id", sql.NVarChar(80), product.id)
      .input("seller_id", sql.NVarChar(80), product.sellerId)
      .input("title", sql.NVarChar(255), product.title || "")
      .input("description", sql.NVarChar(sql.MAX), product.description || "")
      .input("category", sql.NVarChar(160), product.category || "")
      .input("price", sql.Decimal(18, 2), Number(product.price || 0))
      .input("condition", sql.NVarChar(160), product.condition || "")
      .input("location", sql.NVarChar(255), product.location || "")
      .input("image", sql.NVarChar(sql.MAX), product.image || "")
      .input("status", sql.NVarChar(32), product.status || "pending")
      .input("sale_status", sql.NVarChar(32), product.saleStatus || null)
      .input("created_at", sql.DateTime2, dateOrNull(product.createdAt))
      .input("updated_at", sql.DateTime2, dateOrNull(product.updatedAt))
      .query(`
        INSERT INTO ${sqlTable("Products")} (
          id, seller_id, title, description, category, price, condition, location,
          image, status, sale_status, created_at, updated_at
        )
        VALUES (
          @id, @seller_id, @title, @description, @category, @price, @condition, @location,
          @image, @status, @sale_status, @created_at, @updated_at
        )
      `);
  }
}

async function insertFavorites(sql, transaction, favorites) {
  const seen = new Set();
  for (const favorite of favorites.filter(item => item.userId && item.productId)) {
    const key = `${favorite.userId}:${favorite.productId}`;
    if (seen.has(key)) continue;
    seen.add(key);
    await new sql.Request(transaction)
      .input("user_id", sql.NVarChar(80), favorite.userId)
      .input("product_id", sql.NVarChar(80), favorite.productId)
      .query(`INSERT INTO ${sqlTable("Favorites")} (user_id, product_id) VALUES (@user_id, @product_id)`);
  }
}

async function insertChats(sql, transaction, chats) {
  for (const chat of chats.filter(item => item.productId && item.buyerId && item.sellerId)) {
    await new sql.Request(transaction)
      .input("id", sql.NVarChar(80), chat.id)
      .input("product_id", sql.NVarChar(80), chat.productId)
      .input("buyer_id", sql.NVarChar(80), chat.buyerId)
      .input("seller_id", sql.NVarChar(80), chat.sellerId)
      .input("read_by_json", sql.NVarChar(sql.MAX), JSON.stringify(chat.readBy || {}))
      .input("created_at", sql.DateTime2, dateOrNull(chat.createdAt))
      .query(`
        INSERT INTO ${sqlTable("Chats")} (id, product_id, buyer_id, seller_id, read_by_json, created_at)
        VALUES (@id, @product_id, @buyer_id, @seller_id, @read_by_json, @created_at)
      `);
  }
}

async function insertMessages(sql, transaction, messages) {
  for (const message of messages.filter(item => item.chatId && item.senderId)) {
    await new sql.Request(transaction)
      .input("id", sql.NVarChar(80), message.id)
      .input("chat_id", sql.NVarChar(80), message.chatId)
      .input("sender_id", sql.NVarChar(80), message.senderId)
      .input("text", sql.NVarChar(sql.MAX), message.text || "")
      .input("image_url", sql.NVarChar(sql.MAX), message.imageUrl || "")
      .input("type", sql.NVarChar(32), message.type || (message.imageUrl ? "image" : "text"))
      .input("created_at", sql.DateTime2, dateOrNull(message.createdAt))
      .query(`
        INSERT INTO ${sqlTable("Messages")} (id, chat_id, sender_id, text, image_url, type, created_at)
        VALUES (@id, @chat_id, @sender_id, @text, @image_url, @type, @created_at)
      `);
  }
}

async function insertReviews(sql, transaction, reviews) {
  for (const review of reviews.filter(item => item.sellerId && item.buyerId)) {
    await new sql.Request(transaction)
      .input("id", sql.NVarChar(80), review.id)
      .input("seller_id", sql.NVarChar(80), review.sellerId)
      .input("buyer_id", sql.NVarChar(80), review.buyerId)
      .input("rating", sql.Int, Number(review.rating || 0))
      .input("comment", sql.NVarChar(sql.MAX), review.comment || "")
      .input("created_at", sql.DateTime2, dateOrNull(review.createdAt))
      .query(`
        INSERT INTO ${sqlTable("Reviews")} (id, seller_id, buyer_id, rating, comment, created_at)
        VALUES (@id, @seller_id, @buyer_id, @rating, @comment, @created_at)
      `);
  }
}

async function insertNotifications(sql, transaction, notifications) {
  const known = new Set(["id", "userId", "type", "title", "message", "link", "read", "chatId", "senderId", "createdAt"]);
  for (const notification of notifications.filter(item => item.userId)) {
    const extra = {};
    for (const [key, value] of Object.entries(notification)) {
      if (!known.has(key)) extra[key] = value;
    }
    await new sql.Request(transaction)
      .input("id", sql.NVarChar(80), notification.id)
      .input("user_id", sql.NVarChar(80), notification.userId)
      .input("type", sql.NVarChar(64), notification.type || "")
      .input("title", sql.NVarChar(255), notification.title || "")
      .input("message", sql.NVarChar(sql.MAX), notification.message || "")
      .input("link", sql.NVarChar(80), notification.link || "notifications")
      .input("is_read", sql.Bit, Boolean(notification.read))
      .input("chat_id", sql.NVarChar(80), notification.chatId || null)
      .input("sender_id", sql.NVarChar(80), notification.senderId || null)
      .input("extra_json", sql.NVarChar(sql.MAX), Object.keys(extra).length ? JSON.stringify(extra) : null)
      .input("created_at", sql.DateTime2, dateOrNull(notification.createdAt))
      .query(`
        INSERT INTO ${sqlTable("Notifications")} (
          id, user_id, type, title, message, link, is_read, chat_id, sender_id, extra_json, created_at
        )
        VALUES (
          @id, @user_id, @type, @title, @message, @link, @is_read, @chat_id, @sender_id, @extra_json, @created_at
        )
      `);
  }
}

async function insertCartItems(sql, transaction, cartItems) {
  for (const item of cartItems.filter(row => row.userId && row.productId)) {
    await new sql.Request(transaction)
      .input("id", sql.NVarChar(80), item.id)
      .input("user_id", sql.NVarChar(80), item.userId)
      .input("product_id", sql.NVarChar(80), item.productId)
      .input("quantity", sql.Int, Number(item.quantity || 1))
      .input("created_at", sql.DateTime2, dateOrNull(item.createdAt))
      .input("updated_at", sql.DateTime2, dateOrNull(item.updatedAt))
      .query(`
        INSERT INTO ${sqlTable("CartItems")} (id, user_id, product_id, quantity, created_at, updated_at)
        VALUES (@id, @user_id, @product_id, @quantity, @created_at, @updated_at)
      `);
  }
}

async function insertOrders(sql, transaction, orders) {
  for (const order of orders.filter(item => item.userId)) {
    await new sql.Request(transaction)
      .input("id", sql.NVarChar(80), order.id)
      .input("user_id", sql.NVarChar(80), order.userId)
      .input("method", sql.NVarChar(64), order.method || "")
      .input("status", sql.NVarChar(64), order.status || "")
      .input("total", sql.Decimal(18, 2), Number(order.total || 0))
      .input("created_at", sql.DateTime2, dateOrNull(order.createdAt))
      .query(`
        INSERT INTO ${sqlTable("Orders")} (id, user_id, method, status, total, created_at)
        VALUES (@id, @user_id, @method, @status, @total, @created_at)
      `);

    for (const [lineIndex, item] of (order.items || []).entries()) {
      await new sql.Request(transaction)
        .input("order_id", sql.NVarChar(80), order.id)
        .input("line_index", sql.Int, lineIndex)
        .input("product_id", sql.NVarChar(80), item.productId)
        .input("seller_id", sql.NVarChar(80), item.sellerId)
        .input("title", sql.NVarChar(255), item.title || "")
        .input("price", sql.Decimal(18, 2), Number(item.price || 0))
        .input("quantity", sql.Int, Number(item.quantity || 1))
        .query(`
          INSERT INTO ${sqlTable("OrderItems")} (order_id, line_index, product_id, seller_id, title, price, quantity)
          VALUES (@order_id, @line_index, @product_id, @seller_id, @title, @price, @quantity)
        `);
    }
  }
}

async function insertAuthCodes(sql, transaction, authCodes) {
  for (const code of authCodes) {
    await new sql.Request(transaction)
      .input("id", sql.NVarChar(80), code.id)
      .input("email", sql.NVarChar(255), code.email)
      .input("purpose", sql.NVarChar(64), code.purpose)
      .input("code", sql.NVarChar(16), code.code)
      .input("payload_json", sql.NVarChar(sql.MAX), JSON.stringify(code.payload || {}))
      .input("created_at", sql.DateTime2, dateOrNull(code.createdAt))
      .input("expires_at", sql.DateTime2, dateOrNull(code.expiresAt))
      .query(`
        INSERT INTO ${sqlTable("AuthCodes")} (id, email, purpose, code, payload_json, created_at, expires_at)
        VALUES (@id, @email, @purpose, @code, @payload_json, @created_at, @expires_at)
      `);
  }
}

function useSqlServer() {
  return ["sqlserver", "sql_server", "mssql"].includes(STORAGE_DRIVER);
}

async function readDb() {
  if (!useSqlServer()) {
    throw new Error("Backend hien chi cau hinh SQL Server. Vui long cai DB_CLIENT=sqlserver trong .env.");
  }
  return readSqlServerDb();
}

async function writeDb(db) {
  if (!useSqlServer()) {
    throw new Error("Backend hien chi cau hinh SQL Server. Vui long cai DB_CLIENT=sqlserver trong .env.");
  }
  await writeSqlServerDb(db);
}

module.exports = {
  readDb,
  writeDb,
  normalizeDb
};
