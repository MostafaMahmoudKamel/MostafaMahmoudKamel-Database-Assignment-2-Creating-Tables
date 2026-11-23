CREATE DATABASE BidNile;
GO
USE BidNile;
GO

-- 4- schemas 
CREATE SCHEMA Core;
GO
CREATE SCHEMA Logistics;
GO
CREATE SCHEMA Catalog;
GO
CREATE SCHEMA Auction;
GO

--city table
CREATE TABLE Core.City
(
    Id INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_City PRIMARY KEY,

    Name NVARCHAR(60) NOT NULL,

    CountryCode CHAR(2) NOT NULL
        CONSTRAINT CK_City_CountryCode CHECK (CountryCode IN ('EG', 'SA', 'AE')),

    CONSTRAINT UQ_City_NameCountryCode UNIQUE (Name, CountryCode)
);
GO

--Member table
CREATE TABLE Core.Member
(
    Id UNIQUEIDENTIFIER NOT NULL                    --GUID
        CONSTRAINT PK_Member PRIMARY KEY
        CONSTRAINT DF_Member_Id DEFAULT NEWID(),

    FullName NVARCHAR(100) NOT NULL,

    Email VARCHAR(254) NOT NULL
        CONSTRAINT UQ_Member_Email UNIQUE,

    Mobile VARCHAR(16) NOT NULL,

    NationalId VARCHAR(20) NOT NULL
        CONSTRAINT UQ_Member_NationalId UNIQUE,

    BirthDate DATE NOT NULL
        CONSTRAINT CK_Member_BirthDate
        CHECK (BirthDate <= DATEADD(YEAR, -18, CAST(SYSUTCDATETIME() AS DATE))),

    IsVerified BIT NOT NULL
        CONSTRAINT DF_Member_IsVerified DEFAULT 0,

    RegisteredAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT DF_Member_RegisteredAtUtc DEFAULT SYSUTCDATETIME(),

    CityId INT NOT NULL,

    InvitedByMemberId UNIQUEIDENTIFIER NULL,

    CONSTRAINT CK_Member_InvitedByMemberId
        CHECK (InvitedByMemberId IS NULL OR InvitedByMemberId <> Id),

    CONSTRAINT CK_Member_Mobile         
        CHECK (Mobile LIKE '+[0-9]%' AND SUBSTRING(Mobile, 2, 15) NOT LIKE '%[^0-9]%'),

    CONSTRAINT CK_Member_NationalId
        CHECK (NationalId NOT LIKE '%[^A-Za-z0-9]%')
);
GO

CREATE TABLE Core.Wallet
(
    MemberId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT PK_Wallet PRIMARY KEY,

    Balance DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_Wallet_Balance DEFAULT 0
        CONSTRAINT CK_Wallet_Balance CHECK (Balance >= 0),

    HeldAmount DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_Wallet_HeldAmount DEFAULT 0
        CONSTRAINT CK_Wallet_HeldAmount CHECK (HeldAmount >= 0),

    Currency CHAR(3) NOT NULL
        CONSTRAINT DF_Wallet_Currency DEFAULT 'EGP',

    UpdatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT DF_Wallet_UpdatedAtUtc DEFAULT SYSUTCDATETIME(),

    CONSTRAINT CK_Wallet_HeldNotMoreThanBalance CHECK (HeldAmount <= Balance)
);
GO

-- Warehouses storing inspected items with GPS coordinates and single manager
CREATE TABLE Logistics.Warehouse
(
    Id INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Warehouse PRIMARY KEY,

    Name NVARCHAR(80) NOT NULL
        CONSTRAINT UQ_Warehouse_Name UNIQUE,

    Capacity INT NOT NULL
        CONSTRAINT CK_Warehouse_Capacity CHECK (Capacity > 0),

    CityId INT NOT NULL,

    Latitude FLOAT NOT NULL
        CONSTRAINT CK_Warehouse_Latitude CHECK (Latitude BETWEEN -90 AND 90),

    Longitude FLOAT NOT NULL
        CONSTRAINT CK_Warehouse_Longitude CHECK (Longitude BETWEEN -180 AND 180),

    ManagerId UNIQUEIDENTIFIER NULL,
    ManagerSince DATE NULL,

    CONSTRAINT CK_Warehouse_ManagerPair
        CHECK ((ManagerId IS NULL AND ManagerSince IS NULL)
            OR (ManagerId IS NOT NULL AND ManagerSince IS NOT NULL))
);
GO

--Employee table
-- Members who work as warehouse employees
CREATE TABLE Logistics.Employee
(
    MemberId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT PK_Employee PRIMARY KEY,

    WarehouseId INT NOT NULL
);
GO

--Category table
CREATE TABLE Catalog.Category
(
    Code INT NOT NULL
        CONSTRAINT PK_Category PRIMARY KEY,

    NameEn NVARCHAR(50) NOT NULL
        CONSTRAINT UQ_Category_NameEn UNIQUE,

    NameAr NVARCHAR(50) NULL,

    CommissionPercent DECIMAL(4,2) NOT NULL
        CONSTRAINT CK_Category_Commission CHECK (CommissionPercent BETWEEN 0 AND 30),

    ParentCode INT NULL,

    CONSTRAINT CK_Category_NoSelfParent
        CHECK (ParentCode IS NULL OR ParentCode <> Code)
);
GO

--Item table
CREATE TABLE Catalog.Item
(
    Id INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Item PRIMARY KEY,

    Title NVARCHAR(150) NOT NULL,

    Description NVARCHAR(MAX) NULL,

    ConditionScore TINYINT NOT NULL
        CONSTRAINT CK_Item_ConditionScore CHECK (ConditionScore BETWEEN 1 AND 10),

    Specifications JSON NOT NULL,

    ListedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT DF_Item_ListedAtUtc DEFAULT SYSUTCDATETIME(),

    SellerId UNIQUEIDENTIFIER NOT NULL,

    InspectorId UNIQUEIDENTIFIER NULL,

    CategoryCode INT NOT NULL,

    WarehouseId INT NULL,

    CONSTRAINT CK_Item_SellerNotInspector
        CHECK (InspectorId IS NULL OR InspectorId <> SellerId)
);
GO

-- Weak entity for item photos ordered by position (1..20)
CREATE TABLE Catalog.ItemPhoto
(
    ItemId INT NOT NULL,

    Position TINYINT NOT NULL
        CONSTRAINT CK_ItemPhoto_Position CHECK (Position BETWEEN 1 AND 20),

    Url VARCHAR(500) NOT NULL,

    IsMain BIT NOT NULL
        CONSTRAINT DF_ItemPhoto_IsMain DEFAULT 0,

    CONSTRAINT PK_ItemPhoto PRIMARY KEY (ItemId, Position)
);
GO

--Auction table المزاد 
CREATE TABLE Auction.Auction
(
    Id INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Auction PRIMARY KEY,

    ItemId INT NOT NULL,

    StartingPrice DECIMAL(12,2) NOT NULL
        CONSTRAINT CK_Auction_StartingPrice CHECK (StartingPrice > 0),

    ReservePrice DECIMAL(12,2) NULL,

    BidIncrement DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_Auction_BidIncrement DEFAULT 50.00,

    StartAt DATETIMEOFFSET(0) NOT NULL,

    EndAt DATETIMEOFFSET(0) NOT NULL,

    Status VARCHAR(10) NOT NULL
        CONSTRAINT DF_Auction_Status DEFAULT 'Draft'
        CONSTRAINT CK_Auction_Status
            CHECK (Status IN ('Draft', 'Live', 'Ended', 'Cancelled')),

    CONSTRAINT CK_Auction_ReservePrice
        CHECK (ReservePrice IS NULL OR ReservePrice >= StartingPrice),

    CONSTRAINT CK_Auction_EndAfterStart
        CHECK (EndAt > StartAt)
);
GO

-- High-volume bid history with BIGINT counter and unique amount per auction
CREATE TABLE Auction.Bid
(
    Id BIGINT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_Bid PRIMARY KEY,

    AuctionId INT NOT NULL,

    MemberId UNIQUEIDENTIFIER NOT NULL,

    Amount DECIMAL(12,2) NOT NULL
        CONSTRAINT CK_Bid_Amount CHECK (Amount > 0),

    PlacedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT DF_Bid_PlacedAtUtc DEFAULT SYSUTCDATETIME(),

    IpAddress VARCHAR(45) NOT NULL,

    CONSTRAINT UQ_Bid_AuctionAmount UNIQUE (AuctionId, Amount)
);
GO

--AuctionFollower table
CREATE TABLE Auction.AuctionFollower
(
    MemberId UNIQUEIDENTIFIER NOT NULL,

    AuctionId INT NOT NULL,

    FollowedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT DF_AuctionFollower_FollowedAtUtc DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_AuctionFollower PRIMARY KEY (MemberId, AuctionId)
);
GO


-- Task 3 -ALTER: Business Changes =

-- 3.1 Connect all foreign keys (cascade delete only on Item -> ItemPhoto; no action elsewhere)
ALTER TABLE Core.Member
    ADD CONSTRAINT FK_Member_City
        FOREIGN KEY (CityId) REFERENCES Core.City (Id);
GO

-- 3.1 Connect member as Circuler references foreign key
ALTER TABLE Core.Member
    ADD CONSTRAINT FK_Member_InvitedBy
        FOREIGN KEY (InvitedByMemberId) REFERENCES Core.Member (Id);
GO

-- 3.1 Connect  wallet foreign key to member
ALTER TABLE Core.Wallet
    ADD CONSTRAINT FK_Wallet_Member
        FOREIGN KEY (MemberId) REFERENCES Core.Member (Id);
GO

-- 3.1 Connect warehouse foreign key to city
ALTER TABLE Logistics.Warehouse
    ADD CONSTRAINT FK_Warehouse_City
        FOREIGN KEY (CityId) REFERENCES Core.City (Id);
GO

-- 3.1 Connect employee foreign key to member
ALTER TABLE Logistics.Employee
    ADD CONSTRAINT FK_Employee_Member
        FOREIGN KEY (MemberId) REFERENCES Core.Member (Id);
GO

-- 3.1 Connect employee foreign key to warehouse
ALTER TABLE Logistics.Employee
    ADD CONSTRAINT FK_Employee_Warehouse
        FOREIGN KEY (WarehouseId) REFERENCES Logistics.Warehouse (Id);
GO

-- 3.1 Connect warehouse manager foreign key to employee and enforce at most one managed warehouse per manager
ALTER TABLE Logistics.Warehouse
    ADD CONSTRAINT FK_Warehouse_Manager
        FOREIGN KEY (ManagerId) REFERENCES Logistics.Employee (MemberId);
GO

CREATE UNIQUE INDEX UQ_Warehouse_Manager
    ON Logistics.Warehouse (ManagerId) WHERE ManagerId IS NOT NULL;
GO

-- 3.1 Connect category self-referencing parent foreign key
ALTER TABLE Catalog.Category
    ADD CONSTRAINT FK_Category_Parent
        FOREIGN KEY (ParentCode) REFERENCES Catalog.Category (Code);
GO

-- 3.1 Connect item seller foreign key to member
ALTER TABLE Catalog.Item
    ADD CONSTRAINT FK_Item_Seller
        FOREIGN KEY (SellerId) REFERENCES Core.Member (Id);
GO

-- 3.1 Connect item inspector foreign key to member
ALTER TABLE Catalog.Item
    ADD CONSTRAINT FK_Item_Inspector
        FOREIGN KEY (InspectorId) REFERENCES Core.Member (Id);
GO

-- 3.1 Connect item foreign key to category
ALTER TABLE Catalog.Item
    ADD CONSTRAINT FK_Item_Category
        FOREIGN KEY (CategoryCode) REFERENCES Catalog.Category (Code);
GO

-- 3.1 Connect item foreign key to warehouse
ALTER TABLE Catalog.Item
    ADD CONSTRAINT FK_Item_Warehouse
        FOREIGN KEY (WarehouseId) REFERENCES Logistics.Warehouse (Id);
GO

-- 3.1 Connect item photo foreign key with cascading delete when an item is deleted
ALTER TABLE Catalog.ItemPhoto
    ADD CONSTRAINT FK_ItemPhoto_Item
        FOREIGN KEY (ItemId) REFERENCES Catalog.Item (Id)
        ON DELETE CASCADE;
GO

-- 3.1 Connect auction foreign key to item
ALTER TABLE Auction.Auction
    ADD CONSTRAINT FK_Auction_Item
        FOREIGN KEY (ItemId) REFERENCES Catalog.Item (Id);
GO

-- 3.1 Connect bid foreign key to auction
ALTER TABLE Auction.Bid
    ADD CONSTRAINT FK_Bid_Auction
        FOREIGN KEY (AuctionId) REFERENCES Auction.Auction (Id);
GO

-- 3.1 Connect bid foreign key to member
ALTER TABLE Auction.Bid
    ADD CONSTRAINT FK_Bid_Member
        FOREIGN KEY (MemberId) REFERENCES Core.Member (Id);
GO

-- 3.1 Connect auction follower foreign key to member
ALTER TABLE Auction.AuctionFollower
    ADD CONSTRAINT FK_AuctionFollower_Member
        FOREIGN KEY (MemberId) REFERENCES Core.Member (Id);
GO

-- 3.1 Connect auction follower foreign key to auction
ALTER TABLE Auction.AuctionFollower
    ADD CONSTRAINT FK_AuctionFollower_Auction
        FOREIGN KEY (AuctionId) REFERENCES Auction.Auction (Id);
GO

-- 3.2 Add NOT NULL LanguageCode ('ar' or 'en') defaulting to 'ar' for existing and new members in one statement
ALTER TABLE Core.Member
    ADD LanguageCode CHAR(2) NOT NULL
        CONSTRAINT DF_Member_LanguageCode DEFAULT 'ar' --default arabic 
        CONSTRAINT CK_Member_LanguageCode CHECK (LanguageCode IN ('ar', 'en'));
GO

-- 3.3 Add NOT NULL IsFeatured flag defaulting to 0 (No) on items
ALTER TABLE Catalog.Item
    ADD IsFeatured BIT NOT NULL
        CONSTRAINT DF_Item_IsFeatured DEFAULT 0;
GO

-- 3.4 Rename Bid.IpAddress to DeviceIp using sp_rename 
EXEC sp_rename 'Auction.Bid.IpAddress', 'DeviceIp', 'COLUMN';
GO

-- 3.4 Rename Warehouse.Capacity to MaxItems and update its check constraint name
EXEC sp_rename 'Logistics.Warehouse.Capacity', 'MaxItems', 'COLUMN';
GO

EXEC sp_rename 'Logistics.CK_Warehouse_Capacity', 'CK_Warehouse_MaxItems', 'OBJECT';
GO

-- 3.5 Increase Member.FullName length to NVARCHAR(150) while keeping NOT NULL
ALTER TABLE Core.Member
    ALTER COLUMN FullName NVARCHAR(150) NOT NULL; --should add NOT NULL again because the ALTER is remove constraint 
GO

-- 3.6 Drop old check constraint before narrowing MaxItems to SMALLINT (prevents constraint/type conflicts), then enforce > 0 and <= 30000
ALTER TABLE Logistics.Warehouse
    DROP CONSTRAINT CK_Warehouse_MaxItems; -- 1) drop constraint 
GO
ALTER TABLE Logistics.Warehouse
    ALTER COLUMN MaxItems SMALLINT NOT NULL; --2) ALTER  COLUMN
GO
ALTER TABLE Logistics.Warehouse
    ADD CONSTRAINT CK_Warehouse_MaxItems       --3) ADD new constraing again 
        CHECK (MaxItems > 0 AND MaxItems <= 30000);
GO

-- 3.7 Lower maximum category commission from 30% to 25%
ALTER TABLE Catalog.Category
    DROP CONSTRAINT CK_Category_Commission;
GO
ALTER TABLE Catalog.Category
    ADD CONSTRAINT CK_Category_Commission
        CHECK (CommissionPercent BETWEEN 0 AND 25);
GO

-- 3.8 Allow 'PendingReview' auction status and set it as the new default
ALTER TABLE Auction.Auction DROP CONSTRAINT DF_Auction_Status;
GO
ALTER TABLE Auction.Auction DROP CONSTRAINT CK_Auction_Status;
GO
ALTER TABLE Auction.Auction ALTER COLUMN Status VARCHAR(20) NOT NULL;
GO
ALTER TABLE Auction.Auction
    ADD CONSTRAINT CK_Auction_Status
        CHECK (Status IN ('PendingReview', 'Draft', 'Live', 'Ended', 'Cancelled'));
GO
ALTER TABLE Auction.Auction
    ADD CONSTRAINT DF_Auction_Status DEFAULT 'PendingReview' FOR Status;
GO

-- 3.9 Add optional BuyNowPrice column to Auction
ALTER TABLE Auction.Auction
    ADD BuyNowPrice DECIMAL(12,2) NULL;
GO

-- 3.9 Add named CHECK constraint ensuring BuyNowPrice is strictly greater than StartingPrice when provided.
-- Uses WITH CHECK (the default when validating existing rows) so SQL Server verifies all existing rows
-- against the new rule and keeps data integrity enforced, rather than skipping existing rows with NOCHECK.
ALTER TABLE Auction.Auction WITH CHECK
    ADD CONSTRAINT CK_Auction_BuyNowPrice
        CHECK (BuyNowPrice IS NULL OR BuyNowPrice > StartingPrice);
GO

-- 3.10 Enforce uniqueness on Member.Mobile to prevent duplicate accounts
ALTER TABLE Core.Member
    ADD CONSTRAINT UQ_Member_Mobile UNIQUE (Mobile);
GO

-- 3.11 Add optional VerifiedAt timestamp, then drop DF_Member_IsVerified before dropping IsVerified
ALTER TABLE Core.Member
    ADD VerifiedAt DATETIME2(3) NULL;
GO
ALTER TABLE Core.Member DROP CONSTRAINT DF_Member_IsVerified;
GO
ALTER TABLE Core.Member DROP COLUMN IsVerified;
GO

-- 3.12 Create Marketing schema and transfer AuctionFollower into it
CREATE SCHEMA Marketing;
GO
ALTER SCHEMA Marketing TRANSFER Auction.AuctionFollower;
GO








