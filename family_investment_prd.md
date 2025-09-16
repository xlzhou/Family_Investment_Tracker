# Product Requirements Document (PRD)
**Project Name:** Family Investment Tracker (working title)  
**Platform:** iPad (iPhone support in future roadmap)  
**Version:** MVP v1.0  

---

## 1. Overview
The **Family Investment Tracker** is an iPad app designed to help family members record, track, and monitor their investments across multiple asset classes. The app supports multi-user portfolios (Jerry, Carol, Ray, Family), manual entry of buy/sell/dividend/deposit transactions, and automatic fetching of real-time market prices. It provides performance analytics, allocation breakdowns, and dividend history while ensuring security via Face ID/Touch ID and private local/iCloud storage.  

---

## 2. Objectives
- Allow each family member to manage their own portfolio.  
- Consolidate investment records across asset classes (stocks, ETFs, bonds, mutual funds, deposits, crypto).  
- Provide intuitive visualizations of allocation, gains/losses, and dividend history.  
- Secure data storage with privacy-first design (local storage + optional iCloud sync).  
- Offer real-time market value updates at **zero cost** (using free public APIs).  

---

## 3. User Roles
- **Primary User (Admin):** Can create and manage portfolios, add/edit/delete transactions, enable iCloud sync.  
- **Family Users:** Each has a separate portfolio. Can view and add transactions to their own portfolio.  
- **Shared Family Portfolio:** For joint investments.  

---

## 4. Core Features (MVP)

### 4.1 Portfolio Management
- Create multiple portfolios (Jerry, Carol, Ray, Family).  
- Support asset types:  
  - Stocks  
  - ETFs  
  - Bonds  
  - Mutual Funds  
  - Deposits (savings, CDs)  
  - Cryptocurrencies  
  - Other custom/alternative assets  

### 4.2 Transactions
- Manual input of:  
  - **Buy / Sell** (qty, price, date, fees, notes)  
  - **Dividend / Interest** (amount, date, notes)  
  - **Deposit / Withdrawal**  
- Auto-calculation of:  
  - Average cost basis  
  - Realized & unrealized gains/losses  
  - Dividend yield (based on manual entries)  

### 4.3 Market Data
- Auto-fetch current market prices (via free public APIs like Yahoo Finance, Alpha Vantage, or CoinGecko for crypto).  
- Update portfolio valuation in real-time.  
- No automatic dividend fetching (users enter manually for accuracy).  

### 4.4 Reports & Visualization
- **Portfolio Allocation Pie Chart** (by asset class, by family member).  
- **Profit/Loss Line Graph** (over time).  
- **Dividend/Interest Income History** (monthly, yearly).  
- Export to **CSV/PDF** (for tax/accounting).  

### 4.5 Security & Privacy
- Face ID / Touch ID authentication.  
- Local storage on iPad.  
- Optional iCloud sync (encrypted) for sharing across devices.  

---

## 5. Future Features (Roadmap)
- iPhone support (universal app).  
- Push notifications (e.g., dividend payment reminders).  
- Watchlist of potential investments.  
- Tax report generator.  
- Customizable dashboards per user.  

---

## 6. Non-Functional Requirements
- **Performance:** Handle up to 10,000 transactions per portfolio smoothly.  
- **Scalability:** Easy to expand to iPhone and Mac versions.  
- **Cost:** Use free APIs for real-time market data (avoid subscription fees).  
- **Privacy:** All sensitive data stored locally and synced only via iCloud.  

---

## 7. UI / UX Concept (MVP)

### Screen Layouts (Figma-like description)

1. **Login & Security**  
   - Screen: Face ID / Touch ID prompt.  
   - Option: fallback to passcode.  

2. **Portfolio List**  
   - Cards for each portfolio: *Jerry / Carol / Ray / Family*.  
   - Button: ➕ Add Portfolio.  

3. **Portfolio Dashboard**  
   - Header: Current Portfolio Value.  
   - Sections:  
     - Allocation Pie Chart  
     - Profit/Loss Summary  
     - Recent Transactions list.  

4. **Transactions List**  
   - Filter tabs: *All / Buy / Sell / Dividend / Deposit*.  
   - Table-style list with date, type, asset, amount.  
   - Floating button: ➕ Add Transaction.  

5. **Add Transaction Form**  
   - Fields: Asset name/symbol, transaction type, qty, price, fees, date, notes.  
   - Save button.  

6. **Reports Screen**  
   - Tabs: *Allocation / Profit-Loss / Dividends*.  
   - Charts with export button.  

7. **Settings**  
   - Options: iCloud sync toggle, export data, base currency, theme.  

---

## 8. Technical Notes
- **Frontend:** SwiftUI for iPad app.  
- **Backend:** Local Core Data/SQLite storage.  
- **Cloud Sync:** iCloud with CloudKit.  
- **Market Data API:** Yahoo Finance / Alpha Vantage (free tier).  
- **Export:** CSV/PDF via iOS share sheet.  

