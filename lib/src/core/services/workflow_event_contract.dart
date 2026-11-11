// Closed vocabularies prevent free-form data (IDs, addresses, credentials,
// tracking numbers, amounts or server error bodies) entering funnel events.
enum WorkflowAction {
  login,
  registration,
  passwordRecovery,
  trackAdd,
  assemblyCreate,
  paymentQrStart,
  paymentReceipt,
  selfBuyoutCreate,
}

enum WorkflowStage { viewed, started, succeeded, failed, noChange }

enum WorkflowFailure {
  network,
  unauthorized,
  invalidInput,
  conflict,
  server,
  unsuccessfulResult,
  unknown,
}
