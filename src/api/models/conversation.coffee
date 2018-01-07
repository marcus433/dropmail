module.exports =
  name: 'Conversation'
  primaryKey: 'id'
  properties:
    id: 'int'
    count:
      type: 'int'
      default: 0
    subject:
      type: 'string'
      indexed: true
    toSelf:
      type: 'bool'
      default: false
    snoozed:
      type: 'bool'
      default: false
    tag: 'int'
    unread: 'bool'
    hasFiles:
      type: 'bool'
      default: false
    deleted:
      type: 'bool'
      default: false
    messages:
      type: 'list'
      objectType: 'Message'
    participants:
      type: 'list'
      objectType: 'Contact'
    timestamp: 'date'
    lastExchange:
      type: 'Message'
      optional: true
    account: 'Account'
