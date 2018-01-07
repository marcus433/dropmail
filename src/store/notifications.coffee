realm = require '../api/realm'
{ remote: { app } } = require 'electron'
Notification = require 'node-mac-notifier' if process.platform is 'darwin'
#avatar = require '../utils/avatar'

# TODO; add account support so unread state doesn't always show all accounts inbox unread.
class Notifications
  badgeTimeout: null
  constructor: ->
    collection = realm.objects('Conversation').filtered('unread == true && messages.tempFolder.type == 1')
    app.setBadgeCount(collection.length)
    collection.addListener(@updateBadgeCount)
    #realm.objects('Conversation').addListener(@updateNotifications)
  updateNotifications: (collection, changes) =>
    # TODO: batch requests
    window.requestAnimationFrame( =>
      # TODO: only if >= to UIDNEXT OR snoozed
      if changes.insertions.length > 0
        if changes.insertions.length < 4
          for idx in changes.insertions
            conversation = collection[idx]
            new Notification(
              conversation.lastExchange.from[0]?.name
              { body: conversation.subject, canReply: true }
            )
            ###
            if process.platform is 'darwin'
              avatar.fetch({ name: conversation.lastExchange.from[0]?.name, address: conversation.lastExchange.from[0]?.address, tag: conversation.tag })
              .then ({ url }) =>
                new Notification(
                  conversation.lastExchange.from[0]?.name
                  Object.assign({ body: conversation.subject, canReply: true }, if url? then { icon: url } else {})
                )
            else
            ###
        else
          new Notification("#{changes.insertions.length} New Conversations", { body: "#{changes.insertions.length} New Conversations" })
        new Audio('./audio/new.wav').play()
      #else if changes.modifications.length > 0
      # TODO: handle snoozed state.
      return
    )
    return
  updateBadgeCount: (collection, changes) =>
    if changes.insertions.length > 0 or changes.deletions.length > 0
      clearTimeout(@badgeTimeout)
      @badgeTimeout = setTimeout =>
        window.requestAnimationFrame( =>
          app.setBadgeCount(collection.length)
        )
      , 150

module.exports = new Notifications()
