require './_main.scss'
React = require 'react'
ReactDOM = require 'react-dom'
ThreadItem = require '../ThreadItem/Main'
dynamics = require 'dynamics.js'
FlipMove = require 'react-flip-move'
Realm = require '../../api/realm'
Store = require '../../store'

# TODO: rewriteflipmove so it doesn't have access to `item` thus messing with realm when objs are deleted. & no extra items on filter..

rubberBandDistance = (offset, dimension) ->
  constant = 0.55
  scalingFactor = 0.2
  result = (constant * Math.abs(offset) * dimension) / (dimension + constant * Math.abs(offset))
  return scalingFactor*(if offset < 0.0 then -result else result)

UndoView = React.createClass
  displayName: 'UndoView'
  getInitialState: ->
    show: false
    action: null
  componentDidMount: ->
    Realm.objects('Outbox').addListener(@handleOutbox)
  handleOutbox: (collection, changes) ->
    # Why does outbox insert count as a modification..?
    for item in [changes.insertions..., changes.modifications...]
      window.requestAnimationFrame( =>
        @setState({ show: true, action: 'Moved to Trash' })
      )
      # TODO: yield sleep ??
      @undoTimeout = setTimeout( =>
        window.requestAnimationFrame( =>
          @setState({ show: false, action: null })
        )
      , 5000)
  onOver: ->
    clearTimeout(@undoTimeout)
  onOut: ->
    @undoTimeout = setTimeout( =>
      window.requestAnimationFrame( =>
        @setState({ show: false, action: null })
      )
    , 3000)
  onClick: ->
    # TODO: call undo, and ignore onOut.
  componentWillUnmount: ->
    Realm.objects('Outbox').removeListener(@handleOutbox)
  render: ->
    <div className="undo #{if @state.show then 'active' else ''}" onMouseOver={@onOver} onMouseOut={@onOut}>
      <span>{@state.action}</span>
      <span>Undo</span>
    </div>

ScrollView = React.createClass
  displayName: 'ScrollView'
  global: Store.global
  getInitialState: ->
    scrolling: true
    showFilters: false
    offset: 0
    viewport: {
      visible: 0
      first: 0
      last: 0
    }
  componentDidMount: ->
    new Store.unionListeners([
      (callback) => Store.collections.addListener('focus', callback)
      (callback) => Store.collections.focus.addListener(callback)
      (callback) => Store.selections.addListener(callback)
    ], =>
      window.requestAnimationFrame =>
        console.log 'union gave update'
        @forceUpdate()
    )
    ###
    Store.collections.addListener 'focus', =>
      ##
      if @state.offset isnt 50 and @global.state.folder?.type is 4
        @setState(offset: 50)
      else if @state.offset isnt 0
        @setState(offset: 0)
      ##
      #@scroll(true)
      Store.collections.focus?.addListener (collection, changes) =>
        ##
        if Store.collections.focus.length is 0 and @state.offset isnt 0
          @setState(offset: 0)
        ##
        window.requestAnimationFrame =>
          if changes.insertions.length > 0 or changes.deletions.length > 0
            @scroll(true)
            @forceUpdate()
    ###
    ###
    Store.selections.addListener =>
      @forceUpdate()
    ###
    @scroll(true)
    @setState(scrolling: false)
    @scrollTouchDown = false
    window.addEventListener 'scroll-touch-begin', @onScrollTouchDown
    window.addEventListener 'scroll-touch-end', @onScrollTouch
    that = @
    @x = 0
    @locked = false
    @debounceTimeout = null
    @deltas = { x: 0, y: 0 }
    #momentum = false
    ReactDOM.findDOMNode(@refs.container).addEventListener('wheel', @onWheel)
  componentWillUnmount: ->
    window.removeEventListener 'scroll-touch-begin', @onScrollTouchDown
    window.removeEventListener 'scroll-touch-end', @onScrollTouch
    ReactDOM.findDOMNode(@refs.container).removeEventListener('wheel', @onWheel)
  emptyTrash: ->
    return if not @global.state.folder?.isValid()
    Realm.write =>
      Realm.create('Outbox', {
        account: @global.state.accounts[0]
        type: 5
        target: 1
        timestamp: new Date()
        folder: @global.state.folder
      })
  onWheel: (e) ->
    if @locked
      return e.preventDefault()
    else if @scrollTouchDown and not @state.lockSwipe
      @deltas.x += e.deltaX
      @deltas.y += e.deltaY
      absX = Math.abs(@deltas.x)
      absY = Math.abs(@deltas.y)
      if absX > absY + 2
        @locked = true
      ###
      else if absY > absX + 2
        console.log 'lock swiping'
        # TODO lock swiping
      ###
    container = ReactDOM.findDOMNode(@refs.container)
    # TODO bring proper momentum back?
    if container.scrollTop is 0
      scrollTop = (parseFloat(container.style.paddingTop.slice(0,-2)) or 0)
      newBoundsOriginY = scrollTop - @x
      minBoundsOriginY = 0.0
      maxBoundsOriginY = window.innerHeight - 50 # wrong?
      constrainedBoundsOriginY = Math.max(minBoundsOriginY, Math.min(newBoundsOriginY, maxBoundsOriginY))
      rubberBandedY = rubberBandDistance(newBoundsOriginY - constrainedBoundsOriginY, window.innerHeight - 50)
      container.style.paddingTop = Math.abs(constrainedBoundsOriginY + rubberBandedY) + 'px'
      velocity = Math.max(7, Math.abs(e.wheelDelta))
      #momentum = true if not that.scrollTouchDown and velocity > 600
      if @scrollTouchDown
        #or (momentum and velocity > 250)
        clearTimeout(@debounceTimeout)
        if e.wheelDelta < 0
          @x -= velocity
          @x = 0 if @x < 0
        else
        	@x += velocity
        @debounceTimeout = setTimeout =>
          #momentum = false
          if not @scrollTouchDown
            paddingTop = (parseFloat(container.style.paddingTop.slice(0,-2)) or 0)
            if paddingTop > 0
              window.requestAnimationFrame( =>
                dynamics.animate(container, {
                  paddingTop: 0
                }, { type: dynamics.spring, frequency: 1, duration: 500, complete: =>
                  @x = 0
                })
              )
        , 100
  onScrollTouch: ->
    if @locked
      @locked = false
      container = ReactDOM.findDOMNode(@refs.container)
      window.requestAnimationFrame( =>
        dynamics.animate(container, {
          paddingTop: 0
        }, { type: dynamics.spring, frequency: 1, duration: 500, complete: =>
          @x = 0
        })
      )
    @scrollTouchDown = false
    @deltas = { x: 0, y: 0 }
  onScrollTouchDown: ->
    @scrollTouchDown = true
  scroll: (force) ->
    if force isnt true
      @setState(scrolling: true) if not @state.scrolling
      clearTimeout(@scrolltimeout)
      @scrolltimeout = setTimeout =>
        @setState(scrolling:false)
      , 150
    viewport = {}
    viewport.visible = Math.ceil(window.innerHeight / @props.itemHeight)
    viewport.first = Math.max(0, Math.floor((ReactDOM.findDOMNode(@refs.container).scrollTop - @state.offset) / @props.itemHeight))
    viewport.last = Math.min(viewport.first + viewport.visible, Store.collections.focus.length)
    return if viewport.first is @state.viewport.first and viewport.last is @state.viewport.last and force isnt true
    @setState({ viewport })
  itemsForRange: ->
    items = []
    for conversation, position in Store.collections.focus.snapshot().slice(@state.viewport.first, Math.min(Store.collections.focus.length, @state.viewport.last+2))
      continue unless conversation.isValid()
      index = @state.viewport.first+position
      selected = Store.selections.isSelected(index)
      item = {
        id: conversation.id
        name: conversation.lastExchange.from[0]?.name
        address: conversation.lastExchange.from[0]?.address
        cached: conversation.lastExchange.from[0]?.cached
        addressHash: conversation.lastExchange.from[0]?.addressHash
        subject: conversation.subject
        count: conversation.count
        timestamp: conversation.timestamp.getTime()
        tag: conversation.tag
        toSelf: conversation.toSelf
        unread: conversation.unread
        hasFiles: conversation.hasFiles
        snoozed: conversation.snoozed
      }
      items.push(<ThreadItem index={index} item={item} selected={selected} key={conversation.id}></ThreadItem>)
    items
  searchtimeout: null
  search: ->
    clearTimeout(@searchtimeout)
    @searchtimeout = setTimeout =>
      @global.state.search = @refs.search.value
    , 150
  toggleUnread: ->
    @global.state.unread = not @global.state.unread
  toggleSnoozed: ->
    @global.state.snoozed = not @global.state.snoozed
  toggleFilters: ->
    @setState(showFilters: not @state.showFilters)
  toggleFiles: ->
    @global.state.files = not @global.state.files
  render: ->
    ###
    <paper-icon-button icon="date-range" title="attachment"></paper-icon-button>
    <paper-icon-button icon="person-pin" title="attachment"></paper-icon-button>
    ###
    # TODO don't disable disableAllAnimations if new message/deletion during scroll.
    hide = @global.state.folder?.type is 6
    <div className="list-container" style={display: if hide then "none"}>
      <div className="search">
        <div className="flip #{if @state.showFilters then 'flipped' else ''}">
          <figure className="front">
            <iron-icon icon="search"></iron-icon>
            <input ref="search" onKeyUp={@search} placeholder="Search Conversations..."/>
          </figure>
          <figure className="back">
            <paper-icon-button icon="visibility" title="unread" onClick={@toggleUnread}></paper-icon-button>
            <paper-icon-button icon="attachment" title="attachment" onClick={@toggleFiles}></paper-icon-button>
            <paper-icon-button icon="alarm" title="snoozed" onClick={@toggleSnoozed}></paper-icon-button>
          </figure>
        </div>
        <div className="filter #{if @state.showFilters then 'active' else ''}"><paper-icon-button icon="filter-list" onClick={@toggleFilters} /></div>
      </div>
      <div className="message-list" style={overflowY: 'scroll'} onScroll={@scroll} ref="container">
        {
          if @state.offset > 0
            <div className="empty" onClick={@emptyTrash}>
              <svg fill="#FFFFFF" height="24" viewBox="0 0 24 24" width="24" xmlns="http://www.w3.org/2000/svg">
                <path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/>
                <path d="M0 0h24v24H0z" fill="none"/>
              </svg>
              Empty Trash
              <paper-ripple className="circle recenteringTouch" fit></paper-ripple>
            </div>
        }
        <ul className="#{if @state.scrolling then 'scrolling' else ''}" style={height: Store.collections.focus.length * @props.itemHeight, pointerEvents: (if @state.scrolling then 'none' else 'auto'), padding: 0, margin: 0} ref="content">
          {
            if @state.scrolling
              @itemsForRange()
            else
              <FlipMove>
                {@itemsForRange()}
              </FlipMove>
          }
        </ul>
      </div>
      <UndoView />
    </div>

module.exports = ScrollView
