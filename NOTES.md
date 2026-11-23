# BidNile – Notes

## 0. Our 4 schemas, their tables, and why
- core [city, member , wallet] : basics part depends on 
- Logistics [warehouse, employee] : warehouse and staff who work on warehouse
- catalog [category, item , itemPhoto] : about what is being sold
-  Auction [auction, Bid , AuctionFollower ] : contain selling process 

---

## 1. Relationship types: where in BidNile and how mapped
1) Relationships
1:1
Member – Wallet, Member – Employee
The child table uses the parent's key as its own PK + FK: Wallet.MemberId → Member.Id and Employee.MemberId → Member.Id.
Every member has exactly one wallet, and same PK means no second row is possible.
1:N
City → Member
City → Warehouse
Warehouse → Employee
Member → Item (seller)
Member → Item (inspector)
Category → Item
Warehouse → Item
Item → Auction

The FK column sits on the "many" side and points to the PK of the "one" side. Example: Member.CityId → City.Id, Item.SellerId → Member.Id, Auction.ItemId → Item.Id.

M:N
Member – Auction through Bid (has its own data: amount, time, IP) and through AuctionFollower (pure junction).
A junction table with an FK to each side.
AuctionFollower uses the composite PK (MemberId, AuctionId), so nobody follows the same auction twice.
Bid has its own BIGINT PK because the same member can bid many times on the same auction.
Recursive
Member invited by Member, Category parent of Category
A nullable FK in the same table pointing to its own PK: Member.InvitedByMemberId → Member.Id and Category.ParentCode → Category.Code.
NULL means "nobody invited him" / "top-level category".
Circular
Warehouse ↔ Employee
An employee works in a warehouse (Employee.WarehouseId) and a warehouse is managed by an employee (Warehouse.ManagerId).
Both are FKs, each table points to the other, so the FKs are added later with ALTER TABLE (task 3.1).
Weak entity
ItemPhoto
No Id of its own. Its PK is the composite (ItemId, Position).
The FK to Item uses ON DELETE CASCADE, so photos disappear with their item.


---

## 2. Why these data types?

### Why GUID for members?
because  mobile app generates the member ID on the phone,
and if i used IDENTITY can only produced same number to two phone in 
A GUID is globally unique, so any device can create one safely.
`DEFAULT NEWID()` lets the server create one if the app did not send it.

### Why BIGINT for bids?
The business expects hundreds of millions of bids a year.
`INT` , so the counter would overflow within a few years.
`BIGINT` holds numbers up to about 9.2 × 10¹⁸.

### Why FLOAT for GPS but DECIMAL for money?
GPS coordinates are **approximate measurements**
with many decimals, so an approximate type (`FLOAT`) 
is fine. 
Money must be **exact**: `FLOAT` stores binary approximations and small rounding errors appear (for example 0.1 + 0.2 ≠ 0.3), which is unacceptable for balances and bids. `DECIMAL(12,2)` is exact and also enforces the maximum 9,999,999,999.99.

### Why DATETIMEOFFSET for auctions?
Members live in Cairo (+02:00), Riyadh (+03:00) and Dubai (+04:00), and the start and end must keep their offset (for example `2026-12-05 18:30 +04:00`). `DATETIMEOFFSET` stores the offset together with the time. `DATETIME2` would lose it.


---

## 3. Why can't the circular relationship be created inside CREATE TABLE?

A foreign key can only point to a table that **already exists**. `Employee` has a FK to `Warehouse` (where he works) and `Warehouse` has a FK to `Employee` (its manager). Whichever table we create first points to a table that does not exist yet, so SQL Server raises an error. Task 2 also says no FKs inside `CREATE TABLE`.

**Solution:** create both tables without the circular FK, then add it with `ALTER TABLE ... ADD CONSTRAINT FK_Warehouse_Manager` once both exist. `ManagerId` and `ManagerSince` are `NULL`-able so a warehouse can exist before its manager does (the manager is an employee, and an employee needs a warehouse). A filtered unique index on `ManagerId WHERE ManagerId IS NOT NULL` enforces "a person manages one warehouse at most".

---

## 4. The order the tables were filled in, and why

Rows must be inserted so that  FK points to a row that already exists** (parents before children):

1. `City` – depends on nothing.
2. `Member` – needs a city; inviters are inserted before the members they invited (or `InvitedByMemberId = NULL`).
3. `Wallet` – needs its member.
4. `Warehouse` – needs a city; inserted with `ManagerId = NULL` because no employee exists yet.
5. `Employee` – needs a member and a warehouse.
6. `UPDATE Warehouse` – now set `ManagerId` and `ManagerSince` (this closes the circle).
7. `Category` – parents before children (Vehicles before Cars).
8. `Item` – needs seller, category, and optionally inspector and warehouse.
9. `ItemPhoto` – needs its item.
10. `Auction` – needs its item.
11. `Bid` – needs an auction and a member.
12. `AuctionFollower` (now `Marketing.AuctionFollower`) – needs a member and an auction.



---

## 5. The errors in 3.6 and 3.11, and how they were fixed

### 3.6 – `MaxItems` to the smallest type that fits 30,000
- **Type chosen:** `SMALLINT` (up to 32,767). `TINYINT` only goes to 255.
- **Error:** `ALTER TABLE ... ALTER COLUMN MaxItems SMALLINT` fails with a message saying the object `CK_Warehouse_MaxItems` is dependent on the column. The existing `CHECK (MaxItems > 0)` uses the column, and SQL Server does not allow changing a column's type while a constraint depends on it.
- **Fix:**
  1. `DROP CONSTRAINT CK_Warehouse_MaxItems`
  2. `ALTER COLUMN MaxItems SMALLINT NOT NULL`
  3. `ADD CONSTRAINT CK_Warehouse_MaxItems CHECK (MaxItems > 0 AND MaxItems <= 30000)` (keeps `> 0` and adds the new limit).

### 3.11 – drop `IsVerified`
- **Error:** `ALTER TABLE ... DROP COLUMN IsVerified` fails because the object `DF_Member_IsVerified` is dependent on the column. That is its `DEFAULT 0` constraint, which is attached to the column.
- **Fix:** first `DROP CONSTRAINT DF_Member_IsVerified`, then `DROP COLUMN IsVerified`. (`VerifiedAt` was added before, as a nullable column.)


---



