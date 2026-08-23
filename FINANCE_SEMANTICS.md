# Finance semantics

The system uses a manual cash position plus a dated plan. `Account.balance_cents` is the current confirmed cash position. A `Transaction` with status `confirmed` or `paid` is assumed to already be reflected in that account balance and therefore is not replayed in the forecast. Only `planned` transactions are projected on their `expected_on` date (falling back to `occurred_on`).

Open debts are projected separately on their due date by subtracting `outstanding_cents`. Record a planned repayment either as a planned transaction or as the debt due event, not both, unless the repayment is intentionally split and the amounts are adjusted.

This keeps the dashboard conservative and prevents confirmed history from being double-counted. Bank synchronization is out of scope; every manual or voice-entered amount must be reviewed before it is saved.
