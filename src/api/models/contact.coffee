module.exports =
  name: 'Contact'
  primaryKey: 'hash'
  properties:
    name:
      type: 'string'
      default: ''
    address:
      type: 'string'
      indexed: true
    hash: 'string'
    addressHash: 'string'
    cached:
      type: 'bool'
      default: false
    uncacheable:
      type: 'bool'
      default: false
    rank:
      type: 'int'
      default: 0
