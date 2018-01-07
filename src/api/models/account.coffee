module.exports =
  name: 'Account'
  primaryKey: 'address'
  properties:
    name:
      type: 'string'
      default: ''
    address: 'string'
    aliases:
      type: 'list'
      objectType: 'Alias'
    avatar:
      type: 'string'
      optional: true
    oauth:
      type: 'bool'
      default: false
    signature:
      type: 'string'
      default: 'Sent from <a href="https://dropmailapp.com">DropMail</a>'
    configuration: 'string'
