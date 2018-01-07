Promise = require 'bluebird'

class Avatar
  fetch: (conversation) =>
    Promise.reject()
  initials: (name, address) ->
    # TODO name = (conversation.name or '').trim()
    name = (name or '').trim()
    first = null
    last = null
    if name.length is 0
      if '.' in address.split('@')[0]
        first = address.split('.')[0][0]
        last = address.split('.')[1][0]
      else
        first = address[0]
    else
      [first, others..., last] = name.split(' ')
    initials = "#{if first? then first[0].toUpperCase() else ''}#{if last? then last[0].toUpperCase() else ''}"
    initials

module.exports = new Avatar()
