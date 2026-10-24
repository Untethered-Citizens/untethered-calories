# Architecture

A short map of the code and the rules it follows. Read it before changing logging, storage or the dashboard.

## The idea

Logging is a conversation. The user types, dictates or photographs what they ate, and Claude, called with the **user's own Anthropic API key**, turns it into structured entries through tool use. Everything else is plain on-device Swift: storage, totals, the dashboard and weight. There is no backend.

## Stack

Swift and SwiftUI · SwiftData · Swift Charts · HealthKit (weight, read only) · Keychain · `URLSession` calling `POST https://api.anthropic.com/v1/messages` directly, with tool use and prompt caching. Minimum iOS version: 26.

## Code layout (`CalorieTracker/`)

| Folder | What's in it |
|---|---|
| `Core/` | Pure logic with no storage: `LocalDate`, food enums (`FoodTypes`), `Integrity`, `TargetHistory`, `Stats`, `SystemPrompt`, `LogTools`, `ModelPricing` |
| `Models/` | SwiftData `@Model`s (`MealEntry`, `DailySummary`, `Targets`, `UsualMeal`, `TokenUsage`) and `AppSettings` |
| `Services/` | `DataStore.swift` (`DailySummaryStore`, `EntryWriter`, `TargetStore`), `RollUp`, `APIKeyStore` (Keychain), `AnthropicClient`, `LogConversation`, `ToolRunner`, `HealthWeight` |
| `Views/` | SwiftUI screens grouped by area (`Log/`, `Dashboard/`, `Settings/` and so on) |

Tests live in `CalorieTrackerTests/` and use synthetic data only.

## How an entry is logged

1. `LogConversation` sends the current short conversation, plus a small computed context (today's totals, targets), to Claude. The system prompt is cached. Past history is never sent.
2. Claude replies with tool calls, which `ToolRunner` executes.
   - **Path A:** the user gave numbers, or they were read from a label. The entry is committed at once.
   - **Path B:** Claude estimated. The entry is shown as a proposal card and committed only when the user accepts it.
3. Every commit goes through `EntryWriter`, the single write boundary.

## Non-negotiables

- **Dates are local calendar dates**, not UTC timestamps. Back-dated logging is normal.
- **Macro integrity check at the write boundary:** `4P + 4C + 9F` must be within 15% of calories. Entries flagged `containsAlcohol` are exempt. Use named fields only, never positional mapping.
- **Source honesty:** every entry is exactly one of `Label`, `Estimate` or `Photo Estimate`, and an estimate is never promoted to a label. Summaries state the estimated share by calories.
- **DailySummary:** get-or-create by date, with a unique date. Never merge or upsert on date, and never assume a row exists.
- **Sort detail by date, then meal** (Breakfast, Lunch, Dinner, Snack), never by creation order.
- **Gaps are gaps:** never average over missing days, and leave today (partial) out of averages.
- **Claude is only for parsing, estimating and conversation.** All arithmetic, totals, roll-up, retention and dashboard logic are deterministic Swift, with no model call.
- **Keep tokens cheap:** cache the system prompt, and send only the current conversation plus computed context.
- **No accounts, analytics, ads, tracking or backend servers.**
- **No custom encryption.** Only HTTPS through `URLSession`, the Keychain and iOS file protection, declared with `ITSAppUsesNonExemptEncryption = NO`.

## The API key

The key is stored in the Keychain, on this device only, and is never logged. Messages go only after the user has agreed to share data with Anthropic (`AIConsent`). Don't hard-code model IDs from memory: the list of models is fetched from Anthropic and the user picks one.
