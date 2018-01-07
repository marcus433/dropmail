module.exports =
  name: 'Folder'
  properties:
    account: 'Account'
    path: 'string'
    type:
      type: 'int'
      default: 0
      indexed: true
    name: 'string'
    parent:
      type: 'string'
      optional: true
    uidNext:
      type: 'int'
      optional: true
    uidValidity:
      type: 'int'
      optional: true
    exists:
      type: 'int'
      optional: true
    checkpoint:
      type: 'int'
      optional: true
    highestModseq:
      type: 'string'
      optional: true
    firstSync:
      type: 'bool'
      default: false
