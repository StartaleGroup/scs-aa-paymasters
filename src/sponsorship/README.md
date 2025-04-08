# Sponsorship Paymaster Contract - EP v0.7.0

The **Sponsorship Paymaster** contract facilitates **gas sponsorship** for **UserOperations** in **ERC-4337 Account Abstraction**. It securely manages **user balances**, validates **gas sponsorships**, and ensures **secure withdrawals** using **EntryPoint**.

## 🔹 Core Functionalities

### 1️⃣ User Deposits & Gas Sponsorship
- Users deposit **ETH** to fund gas sponsorships.
- Deposits are recorded in `sponsorBalances` and also **transferred to EntryPoint**.
- **Paymaster sponsors UserOperations**, deducting required gas fees from the sender’s deposit.
- A **price markup** (default `1e6` ) allowing **dynamic fee adjustments**. (charging up to 100# premium)

---

### 2️⃣ Secure Paymaster Validation (`_validatePaymasterUserOp`)
- **Parses `paymasterAndData`** to extract:
  - **`sponsorAccount`**: Who pays for the gas.
  - **`validUntil` & `validAfter`**: Ensures time validity.
  - **`feeMarkup`**: Applied to gas fees.
  - **`signature`**: Validates sponsorship authorization.
- **Ensures valid signatures** using **ECDSA recovery**. (any-one-out-of-n-signers using MultiSigner lib)
- **Verifies funding account balance** to cover transaction costs.
- **Deducts gas fees** and stores **context for `_postOp`**.

---

### 3️⃣ Post-Operation Gas Adjustments (`_postOp`)
- **Calculates actual gas costs** and adjusts for **EntryPoint overhead gas**.(unaccountedGas is gas not accounted for postOp and within the entrypoint)
- **Applies price markup** and computes the premium and sends to feeCollector address.(by updating sponsorBalances for the Entrypoint)
- **Refunds excess gas fees** if overcharged.

---

### 4️⃣ User Withdrawals (Delayed Withdrawals)
- Users **request withdrawals** with `requestWithdrawal`.
- **Execute withdrawals via EntryPoint**, ensuring:
  - **Funds exist** in both **user balance & EntryPoint**.
  - **Withdrawal delay is respected**
  - **EntryPoint securely processes the withdrawal**.
- **Re-initiate withdrawal requests** by resetting `lastWithdrawalTimestamp`.

---

### 5️⃣ Admin & Configuration
- **Set minimum deposit** (`setMinDeposit`): Ensures sponsorship viability.
- **Set fee collector** (`setFeeCollector`): Redirects markup profits.
- **Update unaccounted gas** (`setUnaccountedGas`): Ensures accurate gas calculations.
- **Prevent direct deposits** (`deposit()`): Redirects users to `depositFor`.

---

## 🔹 Key Security Features
✔ **Ensures valid user signatures** before sponsoring transactions.  
✔ **Prevents underfunded sponsorships** with strict balance checks.  
✔ **Validates withdrawal requests** with **timelocks** and **EntryPoint balance checks**.  
✔ **Protects against gas abuse** by enforcing a **valid price markup range (`1e6 - 2e6`)**.  
✔ **Mitigates risks from underpayment/overpayment** in `_postOp`.  

---

## 🚀 **How It Works**
✅ **Users deposit ETH** → Paymaster **sponsors gas** → **Validates user signature & balances** → **Adjusts fees dynamically** → **Handles secure refunds & withdrawals** via **EntryPoint**. 🚀

