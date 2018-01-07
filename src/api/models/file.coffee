module.exports =
  name: 'File'
  primaryKey: 'id'
  properties:
    id: 'int'
    message: 'Message'
    partNumber:
      type: 'string'
      optional: true
    mimeType: 'string'
    contentId:
      type: 'string'
      optional: true
    size: 'int'
    filename:
      type: 'string'
      optional: true
    saved:
      type: 'bool'
      default: false
