IF DB_ID(N'tdmu_market') IS NULL
BEGIN
  CREATE DATABASE [tdmu_market];
END
GO

USE [tdmu_market];
GO

IF OBJECT_ID(N'dbo.app_documents', N'U') IS NOT NULL
  DROP TABLE dbo.app_documents;
GO

IF OBJECT_ID(N'dbo.OrderItems', N'U') IS NOT NULL DROP TABLE dbo.OrderItems;
IF OBJECT_ID(N'dbo.CartItems', N'U') IS NOT NULL DROP TABLE dbo.CartItems;
IF OBJECT_ID(N'dbo.Favorites', N'U') IS NOT NULL DROP TABLE dbo.Favorites;
IF OBJECT_ID(N'dbo.Reviews', N'U') IS NOT NULL DROP TABLE dbo.Reviews;
IF OBJECT_ID(N'dbo.Messages', N'U') IS NOT NULL DROP TABLE dbo.Messages;
IF OBJECT_ID(N'dbo.Notifications', N'U') IS NOT NULL DROP TABLE dbo.Notifications;
IF OBJECT_ID(N'dbo.AuthCodes', N'U') IS NOT NULL DROP TABLE dbo.AuthCodes;
IF OBJECT_ID(N'dbo.Chats', N'U') IS NOT NULL DROP TABLE dbo.Chats;
IF OBJECT_ID(N'dbo.Orders', N'U') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID(N'dbo.Products', N'U') IS NOT NULL DROP TABLE dbo.Products;
IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL DROP TABLE dbo.Users;
GO

CREATE TABLE dbo.Users (
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
GO

CREATE TABLE dbo.Products (
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
  CONSTRAINT FK_Products_Users FOREIGN KEY (seller_id) REFERENCES dbo.Users(id)
);
GO

CREATE TABLE dbo.Favorites (
  user_id NVARCHAR(80) NOT NULL,
  product_id NVARCHAR(80) NOT NULL,
  CONSTRAINT PK_Favorites PRIMARY KEY (user_id, product_id),
  CONSTRAINT FK_Favorites_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(id),
  CONSTRAINT FK_Favorites_Products FOREIGN KEY (product_id) REFERENCES dbo.Products(id)
);
GO

CREATE TABLE dbo.Chats (
  id NVARCHAR(80) NOT NULL CONSTRAINT PK_Chats PRIMARY KEY,
  product_id NVARCHAR(80) NOT NULL,
  buyer_id NVARCHAR(80) NOT NULL,
  seller_id NVARCHAR(80) NOT NULL,
  read_by_json NVARCHAR(MAX) NULL,
  created_at DATETIME2 NULL,
  CONSTRAINT FK_Chats_Products FOREIGN KEY (product_id) REFERENCES dbo.Products(id),
  CONSTRAINT FK_Chats_Buyer FOREIGN KEY (buyer_id) REFERENCES dbo.Users(id),
  CONSTRAINT FK_Chats_Seller FOREIGN KEY (seller_id) REFERENCES dbo.Users(id),
  CONSTRAINT CK_Chats_read_by_json CHECK (read_by_json IS NULL OR ISJSON(read_by_json) = 1)
);
GO

CREATE TABLE dbo.Messages (
  id NVARCHAR(80) NOT NULL CONSTRAINT PK_Messages PRIMARY KEY,
  chat_id NVARCHAR(80) NOT NULL,
  sender_id NVARCHAR(80) NOT NULL,
  text NVARCHAR(MAX) NULL,
  image_url NVARCHAR(MAX) NULL,
  type NVARCHAR(32) NULL,
  created_at DATETIME2 NULL,
  CONSTRAINT FK_Messages_Chats FOREIGN KEY (chat_id) REFERENCES dbo.Chats(id),
  CONSTRAINT FK_Messages_Users FOREIGN KEY (sender_id) REFERENCES dbo.Users(id)
);
GO

CREATE TABLE dbo.Reviews (
  id NVARCHAR(80) NOT NULL CONSTRAINT PK_Reviews PRIMARY KEY,
  seller_id NVARCHAR(80) NOT NULL,
  buyer_id NVARCHAR(80) NOT NULL,
  rating INT NOT NULL,
  comment NVARCHAR(MAX) NULL,
  created_at DATETIME2 NULL,
  CONSTRAINT FK_Reviews_Seller FOREIGN KEY (seller_id) REFERENCES dbo.Users(id),
  CONSTRAINT FK_Reviews_Buyer FOREIGN KEY (buyer_id) REFERENCES dbo.Users(id)
);
GO

CREATE TABLE dbo.Notifications (
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
  CONSTRAINT FK_Notifications_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(id),
  CONSTRAINT CK_Notifications_extra_json CHECK (extra_json IS NULL OR ISJSON(extra_json) = 1)
);
GO

CREATE TABLE dbo.CartItems (
  id NVARCHAR(80) NOT NULL CONSTRAINT PK_CartItems PRIMARY KEY,
  user_id NVARCHAR(80) NOT NULL,
  product_id NVARCHAR(80) NOT NULL,
  quantity INT NOT NULL,
  created_at DATETIME2 NULL,
  updated_at DATETIME2 NULL,
  CONSTRAINT UQ_CartItems_user_product UNIQUE (user_id, product_id),
  CONSTRAINT FK_CartItems_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(id),
  CONSTRAINT FK_CartItems_Products FOREIGN KEY (product_id) REFERENCES dbo.Products(id)
);
GO

CREATE TABLE dbo.Orders (
  id NVARCHAR(80) NOT NULL CONSTRAINT PK_Orders PRIMARY KEY,
  user_id NVARCHAR(80) NOT NULL,
  method NVARCHAR(64) NULL,
  status NVARCHAR(64) NULL,
  total DECIMAL(18, 2) NOT NULL,
  created_at DATETIME2 NULL,
  CONSTRAINT FK_Orders_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(id)
);
GO

CREATE TABLE dbo.OrderItems (
  order_id NVARCHAR(80) NOT NULL,
  line_index INT NOT NULL,
  product_id NVARCHAR(80) NOT NULL,
  seller_id NVARCHAR(80) NOT NULL,
  title NVARCHAR(255) NOT NULL,
  price DECIMAL(18, 2) NOT NULL,
  quantity INT NOT NULL,
  CONSTRAINT PK_OrderItems PRIMARY KEY (order_id, line_index),
  CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (order_id) REFERENCES dbo.Orders(id),
  CONSTRAINT FK_OrderItems_Products FOREIGN KEY (product_id) REFERENCES dbo.Products(id),
  CONSTRAINT FK_OrderItems_Seller FOREIGN KEY (seller_id) REFERENCES dbo.Users(id)
);
GO

CREATE TABLE dbo.AuthCodes (
  id NVARCHAR(80) NOT NULL CONSTRAINT PK_AuthCodes PRIMARY KEY,
  email NVARCHAR(255) NOT NULL,
  purpose NVARCHAR(64) NOT NULL,
  code NVARCHAR(16) NOT NULL,
  payload_json NVARCHAR(MAX) NULL,
  created_at DATETIME2 NULL,
  expires_at DATETIME2 NULL,
  CONSTRAINT CK_AuthCodes_payload_json CHECK (payload_json IS NULL OR ISJSON(payload_json) = 1)
);
GO
