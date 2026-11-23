/// A reviewed comment batch has already received its single user confirmation.
/// Other operations retain their existing review, including phase updates.
bool requiresEdeskSendReview(String script,
        {bool commentBatchConfirmed = false}) =>
    script != 'edesk_horas.py' &&
    !(script == 'edesk_comentario.py' && commentBatchConfirmed);
