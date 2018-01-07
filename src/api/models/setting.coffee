module.exports =
  name: 'Setting'
  primaryKey: 'key'
  properties:
    key: 'string'
    value:
      type: 'string'
      optional: true
    state:
      type: 'bool'
      default: true
