Promise = require 'bluebird'
Promise.coroutine.addYieldHandler (yielded) ->
  Promise.all(yielded) if Array.isArray(yielded)
imap = require 'emailjs-imap-client'
realm = require '../realm'
TimSort = require 'timsort'
md5 = require '../../utils/md5'
dateFormat = require 'dateformat'
{ wrap } = require 'async-class'
{ transaction, whereNotIn, sleep, whereIn } = require '../helpers'
CONSTANTS = require '../constants'

SYNC_BATCH_LIMIT = 500

DEFAULT_POLL_FREQUENCY = 30000

INBOX_POLL_FREQUENCY = 10000
NONACTIVE_POLL_FREQUENCY = 600000 # TODO: Improve this

FAST_REFRESH_LIMIT = 200 # ~200 flag updates
SLOW_REFRESH_LIMIT = 500 # ~500 flag updates

SLOW_REFRESH_INTERVAL = 300000 # 5 Minutes
FAST_REFRESH_INTERVAL = 30000 # 30 Seconds
FULL_REFRESH_INTERVAL = 600000 # 10 Minutes TODO TOO FREQUENT (limit to 2k?)

MAX_UIDINVALID = 5

GMAIL_ARCHIVE_RAW = '-has:userlabels -in:inbox -in:sent -in:trash -in:spam -in:draft -in:chat'

# TODO: have action idle default to trash when not in use.

maxMessage = realm.objects('Message').sorted('id', true).find(-> true)
maxConvo = realm.objects('Conversation').sorted('id', true).find(-> true)
maxFile = realm.objects('File').sorted('id', true).find(-> true)
maxConvo = if maxConvo? then maxConvo.id else 0
maxMessage = if maxMessage? then maxMessage.id else 0
maxFile = if maxFile? then maxFile.id else 0

class FolderSync
  lastFlagRefresh: 0
  lastFullRefresh: 0
  uids: []
  idleTimer: null
  events:
    expunge: []
    exists: false
    fetch:
      unread: []
      read: []
  active: true
  tries: 0
  exists: 0
  gmailArchive: false
  setHook: (@outboxHook) =>
  outboxHook: ->
  constructor: (@polling, @folder, backend, syncBackend) ->
    if not @folder.firstSync and syncBackend?
      @backend = syncBackend
      @nextBackend = backend
    else
      @backend = backend
    if @folder.type is CONSTANTS.FOLDER.INBOX
      @POLL_FREQUENCY = INBOX_POLL_FREQUENCY
    else if @folder.type is CONSTANTS.FOLDER.OTHER
      @POLL_FREQUENCY = NONACTIVE_POLL_FREQUENCY
    else
      @POLL_FREQUENCY = DEFAULT_POLL_FREQUENCY
  closeSyncClient: =>
    processing = realm.objects('Folder').filtered('account == $0 && firstSync == false', @folder.account).length
    if processing is 0
      try yield @backend.close()
    @backend = @nextBackend
    @nextBackend = null
  run: =>
    @tries = 0
    @active = true
    if not @backend.hasCapability('IDLE') or @polling or @gmailArchive
      yield sleep(@POLL_FREQUENCY)
      while @active
        @getMessageChanges()
        yield sleep(@POLL_FREQUENCY)
    else
      @backend.select(@folder.path)
    return
  stop: =>
    @active = false
    # TODO stop idling (deselect)
  reset: =>
    status = yield @backend.status(@folder.path)
    transaction(null, =>
      messages = realm.objects('Message').filtered('folder == $0', @folder).snapshot()
      for message in messages
        continue unless message.isValid()
        realm.delete(message.files)
        if message.conversation.messages.length is 1
          realm.delete(message.conversation)
        realm.delete(message)
      @folder.uidNext = status.uidnext
      @folder.uidValidity = status.uidvalidity
      @folder.checkpoint = null
      @folder.highestModseq = status.highestmodseq
      @folder.firstSync = false
      return
    )
    @initialSync()
  initialSync: =>
    status = yield @backend.select(@folder.path) # NOTE: if @backend.client._selectedMailbox is @folder.path
    @gmailArchive = @backend.hasCapability('X-GM-EXT-1') and @folder.type is CONSTANTS.FOLDER.ARCHIVE and @folder.path is '[Gmail]/All Mail'
    @uids = []
    @lastFlagRefresh = 0
    @lastFullRefresh = 0
    yield @getMessageChanges(status)
    if not @folder.firstSync
      { messages, uidnext, highestmodseq, exists } = status
      transaction(null, =>
        if not @folder.checkpoint?
          @folder.checkpoint = @uids[@uids.length - 1]
        if exists is 0 or messages is 0
          Object.assign(@folder, { checkpoint: null, firstSync: true })
          @closeSyncClient()
      )
      @run() if exists is 0 or messages is 0
      return
    @run()
    return
  incrementSync: =>
    return if not @folder.checkpoint or @uids.length is 0
    idx = @backend.client._binSearch(@uids, @folder.checkpoint, (a, b) => (a - b)) + 1
    if idx < 0
      idx = Math.abs(idx) - 1
      return if not lower?
    if idx is 0
      transaction(null, =>
        Object.assign(@folder, { checkpoint: null, firstSync: true })
        @closeSyncClient()
        @run()
        return
      )
      return
    offset = idx - SYNC_BATCH_LIMIT
    offset = if offset < 0 then 0 else offset
    range = [@uids[offset], @uids[idx - 1]]
    subsection = @uids[offset .. idx - 1] if @gmailArchive
    idx = idx - SYNC_BATCH_LIMIT
    checkpoint = @uids[idx - 1]
    try
      messages = yield @backend.fetchMessages({ path: @folder.path, sequence: (if @gmailArchive then subsection.join(',') else range[0]+':'+range[1]), bounds: { low: range[0], high: range[1] + 1 }, byUid: true }, @folder.type)
      transaction(null, =>
        @messagesToConversations(messages)
      )
    catch err
      throw "Sync Failed: "+err
    transaction(null, =>
      failure = false
      try
        if not @folder.checkpoint? or checkpoint < @folder.checkpoint
          @folder.checkpoint = checkpoint
      catch err
        failure = true
        throw "Sync Failed"
      finally
        if idx <= 0 and not failure
          Object.assign(@folder, { checkpoint: null, firstSync: true })
          @closeSyncClient()
          @run()
          return
    )
    return
  onIdle: (type, value) =>
    clearTimeout(@idleTimer)
    return if @gmailArchive
    if type is 'expunge'
      deletedUid = @uids[value - 1]
      @uids.splice(value - 1, 1)
      @events.expunge.push(deletedUid)
    else if type is 'exists'
      @exists = value
      @events.exists = true
    else if type is 'fetch'
      return if not (value.flags? and value['#']?)
      value.uid = @uids[value['#'] - 1] if not value.uid?
      unread = if '\\Seen' in value.flags then 'read' else 'unread'
      @events.fetch[unread].push(value.uid)
    @idleTimer = setTimeout(@idleHandler, 150) # TODO: 100 ms?
  idleHandler: =>
    if @events.exists
      @syncNewMessages()
    if @events.expunge.length or @events.fetch.unread.length or @events.fetch.read.length
      transaction(null, =>
        @deleteUids(@events.expunge)
        if @events.fetch.read.length
          messages = @batchWhereIn(realm.objects('Message').filtered('folder == $0 && unread == true', @folder), @events.fetch.read, (idx) -> "uid == $#{idx}")
          for message in messages
            @setMessageUnread(message, false)
        if @events.fetch.unread.length
          messages = @batchWhereIn(realm.objects('Message').filtered('folder == $0 && unread == false', @folder), @events.fetch.unread, (idx) -> "uid == $#{idx}")
          for message in messages
            @setMessageUnread(message, true)
        return
      )
    # TODO: delay following expunge transaction [Maybe due to tx queue??]
    @events.exists = false
    @events.expunge = []
    @events.fetch.unread = []
    @events.fetch.read = []
  getMessageChanges: (status) =>
    didChange = false
    return if not navigator.onLine
    status = yield @backend.status(@folder.path) if not status?
    @exists = status.exists ? status.messages
    if status.uidvalidity > @folder.uidValidity
      throw 'Sync failed' if @tries is 5
      @tries++
      return @reset()
    changed = {}
    if not @backend.hasCapability('UIDNEXT') or status.uidnext > @folder.uidNext or @gmailArchive
      @syncNewMessages()
    else
      transaction(null, =>
        @outboxHook(@folder)
        @collectTrash()
      )
    if new Date().getTime() - @lastFullRefresh >= FULL_REFRESH_INTERVAL
      @fullFlagCheck(status)
    else if @backend.hasCapability('CONDSTORE')
      @condstoreFlagCheck(status) if @folder.highestModseq isnt status.highestmodseq or @folder.exists isnt @exists or @folder.uidNext isnt status.uidnext
    else
      @quickFlagCheck(status)
  expungeUidCache: (deleted) =>
    for uid in deleted
      idx = @backend.client._binSearch(@uids, uid, (a, b) => (a - b)) + 1
      continue if idx < 0
      @uids.splice(idx, 1)
    return
  condstoreFlagCheck: (status) =>
    refresh_limit = FAST_REFRESH_LIMIT
    resetTimer = false
    if new Date().getTime() - @lastFlagRefresh >= SLOW_REFRESH_INTERVAL
      refresh_limit = SLOW_REFRESH_LIMIT
      resetTimer = true
    uidOptions = {}
    uidOptions['X-GM-RAW'] = GMAIL_ARCHIVE_RAW if @gmailArchive
    seen = yield @backend.uids(@folder.path, Object.assign({ seen: true, modseq: new Number(@folder.highestModseq).valueOf() }, uidOptions))
    unseen = yield @backend.uids(@folder.path, Object.assign({ unseen: true, modseq: new Number(@folder.highestModseq).valueOf() }, uidOptions))
    removed = []
    if seen.length > 0
      seen = @batchWhereIn(realm.objects('Message').filtered('folder == $0 && unread != false', @folder), seen, (idx) -> "uid == $#{idx}")
    if unseen.length > 0
      unseen = @batchWhereIn(realm.objects('Message').filtered('folder == $0 && unread != true', @folder), unseen, (idx) -> "uid == $#{idx}")
    if @folder.exists isnt @exists or @folder.uidNext isnt status.uidnext
      messages = realm.objects('Message').filtered('folder == $0', @folder).sorted('timestamp', true)[0...refresh_limit]
      if messages.length > 0
        { timestamp } = messages[messages.length - 1]
        since = dateFormat(timestamp, "dd-mmm-yyyy")
        uids = yield @backend.uids(@folder.path, { since })
        TimSort.sort(uids, (a, b) -> a - b)
        localUids = messages.map((message) -> message.uid)
        removed = @difference(localUids, uids)
        # TODO: if @gmailArchive fetch old-new uids & push them to uid cache.
    transaction(null, =>
      Object.assign(@folder, { highestModseq: status.highestmodseq, exists: @exists })
      @expungeUidCache(removed)
      @invalidatePurgedMessages()
      @deleteUids(removed)
      for message in seen
        @setMessageUnread(message, false)
      for message in unseen
        @setMessageUnread(message, true)
      return
    )
    @lastFlagRefresh = new Date().getTime() if resetTimer
  quickFlagCheck: (status) =>
    refresh_limit = FAST_REFRESH_LIMIT
    resetTimer = false
    if new Date().getTime() - @lastFlagRefresh >= SLOW_REFRESH_INTERVAL
      refresh_limit = SLOW_REFRESH_LIMIT
      resetTimer = true
    messages = realm.objects('Message').filtered('folder == $0', @folder).sorted('timestamp', true)[0...refresh_limit]
    return if messages.length is 0
    { timestamp } = messages[messages.length - 1]
    since = dateFormat(timestamp, "dd-mmm-yyyy")
    uidOptions = {}
    uidOptions['X-GM-RAW'] = GMAIL_ARCHIVE_RAW if @gmailArchive
    seen = yield @backend.uids(@folder.path, Object.assign({ seen: true, since }, uidOptions))
    unseen = yield @backend.uids(@folder.path, Object.assign({ unseen: true, since }, uidOptions))
    uids = [seen..., unseen...]
    TimSort.sort(uids, (a, b) -> a - b)
    localUids = realm.objects('Message').filtered('folder == $0', @folder).sorted('timestamp', true)[0...refresh_limit].map((message) -> message.uid)
    removed = @difference(localUids, uids)
    # TODO: if @gmailArchive fetch old-new uids & push them to uid cache.
    if seen.length > 0
      seen = @batchWhereIn(realm.objects('Message').filtered('folder == $0 && unread != false', @folder), seen, (idx) -> "uid == $#{idx}")
    if unseen.length > 0
      unseen = @batchWhereIn(realm.objects('Message').filtered('folder == $0 && unread != true', @folder), unseen, (idx) -> "uid == $#{idx}")
    transaction(null, =>
      Object.assign(@folder, { exists: @exists })
      @expungeUidCache(removed)
      @invalidatePurgedMessages()
      @deleteUids(removed)
      for message in seen
        @setMessageUnread(message, false)
      for message in unseen
        @setMessageUnread(message, true)
      return
    )
    @lastFlagRefresh = new Date().getTime() if resetTimer
  fullFlagCheck: (status) =>
    if @folder.exists isnt @exists or @folder.uidNext isnt status.uidnext or @folder.highestModseq isnt status.highestmodseq or @lastFullRefresh is 0
      uidOptions = {}
      uidOptions['X-GM-RAW'] = GMAIL_ARCHIVE_RAW if @gmailArchive
      seen = yield @backend.uids(@folder.path, Object.assign({ seen: true }, uidOptions))
      unseen = yield @backend.uids(@folder.path, Object.assign({ unseen: true }, uidOptions))
      # snoozed = yield @backend.uids(@folder.path, { keyword: 'DMSZ' })
      general = { seen, unseen }
      uids = [general.seen..., general.unseen...]
      TimSort.sort(uids, (a, b) -> a - b)
      @uids = uids
      localUids = realm.objects('Message').filtered('folder == $0 && deleted == false', @folder).snapshot().map((message) -> message.uid)
      added = []
      removed = @difference(localUids, @uids)
      added = @difference(@uids, localUids) if @gmailArchive
      if added.length > 0
        added = yield @backend.fetchMessages({ path: @folder.path, sequence: added.join(','), bounds: { low: added[0]  }, byUid: true }, @folder.type)
      seen = []
      unseen = []
      if general.seen.length > 0
        seen = @batchWhereIn(realm.objects('Message').filtered('folder == $0 && unread != false', @folder), general.seen, (idx) -> "uid == $#{idx}")
      if general.unseen.length > 0
        unseen = @batchWhereIn(realm.objects('Message').filtered('folder == $0 && unread != true', @folder), general.unseen, (idx) -> "uid == $#{idx}")
      transaction(null, =>
        Object.assign(@folder, { highestModseq: status.highestmodseq, exists: @exists })
        @expungeUidCache(removed)
        @invalidatePurgedMessages()
        @deleteUids(removed)
        # TODO: is added[0] lowest number in set?
        if added.length > 0
          @messagesToConversations(added)
        for message in seen
          @setMessageUnread(message, false)
        for message in unseen
          @setMessageUnread(message, true)
        return
      )
    @lastFullRefresh = new Date().getTime()
  syncNewMessages: =>
    uidOptions = { uid: '*' }
    if @gmailArchive
      uidOptions.uid = @folder.uidNext+':*'
      uidOptions['X-GM-RAW'] = GMAIL_ARCHIVE_RAW
    latest = yield @backend.uids(@folder.path, uidOptions)
    # TODO: what if doesnt support uidNext?
    # TODO: uidNext needs to be adjusted for ?
    if latest[0]? and latest[0] >= @folder.uidNext
      messages = yield @backend.fetchMessages({ path: @folder.path, sequence: (if @gmailArchive then latest.join(',') else @folder.uidNext+':*'), bounds: { low: @folder.uidNext }, byUid: true }, @folder.type)
      transaction(null, =>
        if messages.length is 0
          @folder.uidNext = (latest[0] ? @folder.uidNext) + 1
          @outboxHook(@folder)
          @collectTrash()
          return
        uids = @messagesToConversations(messages)
        TimSort.sort(uids, (a, b) -> a - b)
        if @uids.length is 0 or uids[0] > @uids[@uids.length - 1]
          for uid in uids
            @uids.push(uid)
        if uids[uids.length - 1] >= @folder.uidNext
          @folder.uidNext = (uids[uids.length - 1] ? @folder.uidNext) + 1
          @outboxHook(@folder)
          @collectTrash()
        return
      )
    else
      transaction(null, =>
        @outboxHook(@folder)
        @collectTrash()
      )
  collectTrash: =>
    conversations = realm.objects('Conversation').filtered('deleted == true && account == $0', @folder.account).snapshot()
    for conversation in conversations
      continue unless conversation.isValid()
      @hardDeleteConversation(conversation)
    return
  invalidatePurgedMessages: =>
    invalidated = realm.objects('Message').filtered('tempFolder == $0 && deleted == true && folder != $0', @folder).snapshot()
    for message in invalidated
      continue unless message.isValid()
      message.tempFolder = null
      if message.conversation.messages.filtered('deleted == false').length is 0
        message.conversation.deleted = true
    return
  tagConversation: (address, unsubscribe) =>
    #['social', 'personal', 'service', 'newsletter']
    tag = 1
    if unsubscribe?.length > 0
      tag = 3
    else if /^linkedin|twitter|facebook(mail)?|plus\\.google|spring\\.me|habbo|vkontakte|taggedmail|accounts\\.google|netlogmail|flixstermail|email\\.classmates|sonicomail|mx\\.plaxo|odnoklassniki|flickr|wwwemail\\.weeworld|last\\.fm|myspace|myheritage|mixi\\.jp|cyworld|gaiaonline|deviantart|skyrock|weheartit|stumblemail|foursquare|fotolog|friendsreunited|livejournal|studivz|@geni|mail\\.goodreads|tuenti|busuu|@xing|nasza-klasa|hyves|whereareyounow|soundcloudmail|australia\\.care2|t\\.caringbridge|delicious|opendiaryplus|email\\.livemocha|service@trombi|weread-mailer|iwiw\\.hu|admin\\.ibibo|43things|@ravelry|mocospace|no-reply@jiepangmail|couchsurfing|@itsmy|mailer\\.etoro|kiwibox|dxy\\.cn|getglue|vampirefreaks|fotki\\.com|englishbaby|travbuddy|nexopia|librarything|cafemom\\.com|notify\\.fetlifemail|fubar\\.com|zoo\\.gr|faces\\.com|irc-galleria|admin@ryze\\.com|reverbnation|mymfb\\.com|cross.tv|skoob.com.br|indabamusic|hospitalityclub\\.org|partyflock|travellerspoint|gamerdna|filmaffinity|laibhaari|academia\\.edu|faceparty|@mubi\\.com|info@hr\\.com|hedda\\.user\\.lysator\\.liu|cozycot\\.com|patientslikeme|support@gays\\.com|blogster|wiser\\.org|writeaprisoner|zooppa|touchtalent|fuelmyblog|dol2day@dolnow|hubculture|ngopost\\.org|admin@notify\\.vk/i.test(address)
      tag = 0 # TODO: why doesn't first one catch jobs-noreply@linkedin.com
    else if /^news|reply|customer|feedback|support|market|info|notification|ebay|linkedin|deliver|subscription|service|mailer|flipboard|twitter|pinterest|booking\\.com|leumi-card|nytimes|boxteam|businessinsider|everestgear|ebookers|reminder|itunes|-update|justdeals|sportsauthority|sysmail|amazon|report@|hello@|maillist|ynet\\.co|appannie|alert|deals|publisher|online|buy|reuters|ups\\.|@about|membership|^mail@|bmw\\.de|stiftung-warentest|overblog|inscription|register|community|scout24|aolmember|admin@|facebookmail|otherinbox|rakuten|bounces|skydrive|insideapple|promotion@|bounce|communication|corporate|getpocket|@yad2|automated|auto-contact|moltoapp|atom\\.io|clalit\\.org|remind@|alibaba/i.test(address)
      tag = 2
    tag
  messagesToConversations: (messages, disallowUid) =>
    uids = []
    for message, x in messages
      uids.push(message.uid) if not disallowUid
      messageIdHeader = message.id
      message.id = ++maxMessage
      message.messageId = messageIdHeader
      existing = realm.objects('Message').filtered('folder == $0 && uid == $1 && deleted == false', @folder, message.uid).find(-> true)
      continue if existing?
      cleanSubject = message.subject.replace(/([\[\(] *)?(RE|FWD?|AW|WG) *([-:;)\]][ :;\])-]*|$)|\]+ *$/igm, '')
      message.prefix = message.subject.split(cleanSubject)[0] ? ''
      cleanSubject = cleanSubject.trim()
      message.timestamp = new Date(message.sentDate)
      message.participants = []
      participantVals = []
      participantMap = new Set()
      participantReferences = {}
      idx = 0
      pushParticipant = ({ name, address }) ->
        newName = name?.trim() ? null
        address = address.toLowerCase()
        if newName?.length
          names = newName.split(' ')
          newName = (n.charAt(0).toUpperCase() + n.slice(1) for n in names).join(' ')
        else
          addressParts = address.split('@')
          userParts = addressParts[0].split(/\_|\-|\./)
          hostParts = addressParts[1].split(/\_|\-|\./)
          [hostParts..., extension] = hostParts
          # TODO filter out common things like service, no-reply, email etc
          newName = (n.charAt(0).toUpperCase() + n.slice(1) for n in userParts).join(' ')
        participantVals.push(address)
        hash = md5(name.toLowerCase()+address)
        addressHash = md5(address)
        participantMap.add(address)
        participantReferences[name+address] = realm.create('Contact', { hash, name: newName, address, addressHash }, true)
        message.participants.push(participantReferences[name+address])
        idx++
      pushParticipant(contact) for contact in message.to
      pushParticipant(contact) for contact in message.cc
      pushParticipant(contact) for contact in message.from
      pushParticipant(contact) for contact in message.replyTo
      pushParticipant(contact) for contact in message.bcc
      conversations = @batchWhereIn(
        realm.objects('Conversation').filtered('account == $0 && subject == $1', @folder.account, cleanSubject),
        participantVals,
        (idx) -> "(participants.address ==[c] $#{idx})"
      )
      conversation = null
      for convo in conversations
        continue unless convo.isValid()
        overlap = 0
        # TODO: if multiple match, it should choose the one with the most matches
        sessionAddresses = new Set()
        for { address } in convo.participants
          if sessionAddresses.has(address)
            continue
          else
            sessionAddresses.add(address)
          if participantMap.has(address)
            overlap++
          if overlap >= 2 or overlap is participantMap.size
            conversation = convo
            break
        sessionAddresses.clear()
        sessionAddresses = null
      toCheck = false
      fromCheck = false
      referencesSelf = false
      participantString = ''
      toMap = {}
      message.to = message.to.map(({ name, address }) =>
        address = address.toLowerCase()
        toMap[address] = true
        toCheck = true if address is @folder.account.address
        ref = participantReferences[name+address]
        ref.rank++
        participantString += ref.hash
        ref
      )
      message.from = message.from.map(({ name, address }) =>
        address = address.toLowerCase()
        referencesSelf = true if toMap[address]
        fromCheck = true if address is @folder.account.address
        ref = participantReferences[name+address]
        ref.rank++
        participantString += ref.hash
        ref
      )
      message.cc = message.cc.map(({ name, address }) =>
        address = address.toLowerCase()
        toCheck = true if address is @folder.account.address
        ref = participantReferences[name+address]
        ref.rank++
        participantString += ref.hash
        ref
      )
      toMap = null
      message.bcc = message.bcc.map(({ name, address }) ->
        address = address.toLowerCase()
        ref = participantReferences[name+address]
        ref.rank++
        participantString += ref.hash
        ref
      )
      message.replyTo = message.replyTo.map(({ name, address }) ->
        address = address.toLowerCase()
        ref = participantReferences[name+address]
        ref.rank++
        participantString += ref.hash
        ref
      )
      message.toSelf = if toCheck and fromCheck then true else false
      message.folder = @folder
      message.tempFolder = @folder
      if message.label?
        tempFolder = realm.objects('Folder').filtered('account == $0 && type == $1', @folder.account, message.label).find(-> true)
        if tempFolder
          message.tempFolder = tempFolder
        else
          message.tempFolder = @folder
      else
        message.tempFolder = @folder
      # TODO: don't use stringify. generate custom maps.
      message.references = message.references.join(' ')
      serverIdDigest =
        messageIdHeader+
        JSON.stringify(message.bodystructure)+
        message.subject+
        participantString+
        message.references
      message.serverId = new Date(message.sentDate).getTime()+md5(serverIdDigest)
      query = 'conversation.account.address ==[c] $0 && serverId == $1'
      query += "&& (tempFolder.type == #{message.folder.type} || tempFolder == null)" if referencesSelf
      duplicates = realm.objects('Message').filtered(query, @folder.account.address, message.serverId).snapshot()
      messageOverwritten = false
      # TODO if targetFolder is null and it is deleted we should replace that duplicate and not resort to deleting extras.
      if duplicates.length is 1
        conversation = null
        interim = duplicates[0]
        interim.folder = message.folder
        interim.tempFolder = message.folder
        if message.label?
          tempFolder = realm.objects('Folder').filtered('account == $0 && type == $1', @folder.account, message.label).find(-> true)
          if tempFolder
            interim.tempFolder = tempFolder
          else
            interim.tempFolder = message.folder
        else
          interim.tempFolder = message.folder
        interim.uid = message.uid
        interim.messageId = message.messageId
        interim.inReplyTo = message.inReplyTo
        interim.unread = message.unread
        interim.deleted = if disallowUid then true else false
        interim.snoozedTo = message.snoozedTo
        interim.references = message.references
        message = interim
        conversation = interim.conversation
        if conversation.unread and not message.unread
          unreadValid = conversation.messages.filtered('unread == true').find(-> true)
          conversation.unread = false if not unreadValid?
        messageOverwritten = true
      else if duplicates.length > 1
        # IDEA: if there is > 1 duplicate we can pioritize by folder. eg inbox duplicate is more important than sent, etc.
        # TODO: dont delete duplicate number 1.
        # TODO: this screws up outbox references
        # TODO: allowing draft to be deleted with undeleted convo may lead to problems?
        for duplicate in duplicates
          continue unless duplicate.isValid()
          realm.delete(duplicate.files)
        realm.delete(duplicates)
      if not conversation?
        conversation = realm.create('Conversation', {
          id: ++maxConvo
          subject: cleanSubject
          toSelf: false
          tag: 1
          unread: false
          timestamp: message.timestamp
          account: @folder.account
        })
      conversation.deleted = false
      conversation.unread = true if message.unread
      if message.timestamp.getTime() >= conversation.timestamp.getTime()
        conversation.timestamp = message.timestamp
        # TODO: tag should only be updated if from isn't ME otherwise everything will jsut be "Personal"
        conversation.tag = @tagConversation(message.from[0]?.address, message.unsubscribe) ? 1
      messageRealm = {}
      if messageOverwritten
        messageRealm = message
      else
        participants = new Set()
        existing = conversation.participants.map(({ hash }) -> hash)
        for ref in message.participants
          { name, address, hash } = ref
          if hash not in existing and not participants.has(hash)
            conversation.participants.push(ref)
          participants.add(hash)
        conversation.toSelf = if participants.size > 1 then false else true
        message.conversation = conversation
        idx = conversation.messages.push(message) - 1
        messageRealm = conversation.messages[idx]
      if not conversation.lastExchange? or message.timestamp > conversation.lastExchange.timestamp
        conversation.lastExchange = messageRealm
        conversation.snoozed = messageRealm.snoozedTo?  # if latest message isnt snoozed, convo shouldn't be.
      files = @backend.getFiles(message.bodystructure, messageRealm) or []
      for file in files
        file.id = ++maxFile
      messageRealm.files = files
      conversation.hasFiles = true if not conversation.hasFiles and files.length > 0
      # TODO; if this does become intensive there are ways to "weave" it in... just prefer not to.
      hashmap = {}
      count = conversation.messages.length
      toselfs = conversation.messages.filtered('toSelf == true').snapshot()
      for message in toselfs
        count-- if hashmap[message.serverId]
        hashmap[message.serverId] = true
      conversation.count = count
      uids.push(conversation) if disallowUid
    uids
  deleteUids: (uids) =>
    return if uids.length is 0
    messages = @batchWhereIn(realm.objects('Message').filtered('folder == $0', @folder), uids, (idx) -> "uid == $#{idx}")
    for message in messages
      continue unless message.isValid()
      active = message.conversation.messages.filtered('deleted == false')
      # TODO: if tempFolder nulled, remove extraneous duplicates...
      if active.length > 1
        # TODO: if no body or draft then don't mark message, just delete and rollback conversation
        message.tempFolder = null if message.tempFolder?.path is message.folder.path
        message.deleted = true
      else if not message.deleted
        message.tempFolder = null if message.tempFolder?.path is message.folder.path
        message.deleted = true
        if not message.tempFolder? # TODO: this check doesn't appear to be functioning.
          message.conversation.deleted = true
    return
  hardDeleteConversation: (conversation) =>
    messages = conversation.messages.filtered('folder == $0', @folder).snapshot()
    if messages.length > 0
      track = messages[0]
      for message in messages[1...]
        continue unless message.isValid()
        realm.delete(message.files)
        realm.delete(message)
      realm.delete(conversation) if conversation?.isValid()
      realm.delete(track) if track?.isValid()
    return
  setMessageUnread: (message, unread) =>
    message.unread = unread
    if message.conversation.messages.length is 1
      message.conversation.unread = unread
    else if message.conversation.unread isnt message.unread
      if unread
        message.conversation.unread = true
      else
        unreadMgs = message.conversation.messages.filtered('unread == true')
        if unreadMgs.length is 0
          message.conversation.unread = false
  difference: (old, latest, rehash, latestHash) ->
    hash = latestHash or {}
    result = []
    oldHash = {}

    hash[i] = true for i in latest if not latestHash

    hash[latest.length] = false

    if rehash
      for i in old
        oldHash[i] = true
        if hash[i] is undefined
          result.push(i)
        else if hash[i] is false
          break
      return [result, oldHash]
    else
      for i in old
        if hash[i] is undefined
          result.push(i)
        else if hash[i] is false
          break

    result
  batchWhereIn: (realmQuery, items, iterator) ->
    results = []
    batchSize = 10000 # NOTE: dependent on number of args chrome v8 will allow. Realm itself doesn't give a shit.
    if items.length > batchSize
      batches = Math.ceil(items.length / batchSize)
      for batch in [1 .. batches]
        start = (batch * batchSize) - batchSize
        itemSet = items[start ... start + batchSize]
        query = ''
        for idx in [0 ... itemSet.length]
          query += iterator(idx)
          query += ' || '
        query = query[0 ... query.length - 4]
        for item in realmQuery.filtered(query, itemSet...).snapshot()
          continue unless item.isValid()
          results.push(item)
    else
      query = ''
      for idx in [0 ... items.length]
        query += iterator(idx)
        query += ' || '
      query = query[0 ... query.length - 4]
      if items.length isnt 0
        results = realmQuery.filtered(query, items...).snapshot()
    results

module.exports = wrap FolderSync
