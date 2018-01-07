module.exports =
  name: 'Message'
  primaryKey: 'id'
  properties:
    id: 'int'
    serverId: 'string'
    folder: 'Folder'
    tempFolder: 'Folder'
    uid: 'int'
    unread: 'bool'
    deleted:
      type: 'bool'
      default: false
    prefix: 'string'
    timestamp: 'date'
    snoozedTo:
      type: 'date'
      optional: true
    unsubscribe:
      type: 'string'
      optional: true
    body:
      type: 'string'
      optional: true
    toSelf: 'bool'
    files:
      type: 'list'
      objectType: 'File'
    to:
      type: 'list'
      objectType: 'Contact'
    from:
      type: 'list'
      objectType: 'Contact'
    cc:
      type: 'list'
      objectType: 'Contact'
    bcc:
      type: 'list'
      objectType: 'Contact'
    replyTo:
      type: 'list'
      objectType: 'Contact'
    messageId: 'string'
    inReplyTo:
      type: 'string'
      optional: true
    references:
      type: 'string'
      optional: true
    conversation: 'Conversation'
