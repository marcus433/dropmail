# TODO: add primaryKey??
module.exports =
  name: 'Outbox'
  properties:
    account: 'Account'
    type: 'int'
    target: 'int'
    initialState:
      type: 'string'
      optional: true
    targetState:
      type: 'string'
      optional: true
    waitingForIMAP:
      type: 'bool'
      default: false
    timestamp: 'date'
    conversations:
      type: 'list'
      objectType: 'Conversation'
    message: 'Message'
    folder: 'Folder'
    attempts:
      type: 'int'
      default: 0
