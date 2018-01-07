require './_main.scss'
React = require 'react'
ReactDOM = require 'react-dom'
dynamics = require 'dynamics.js'
{ MorphReplace } = require 'react-svg-morph'
{ ipcRenderer } = require 'electron'

Store = require '../../store'
SwipeController = require '../../store/swipe'

ipcRenderer.on 'scroll-touch-begin', ->
  window.dispatchEvent(new Event('scroll-touch-begin'))
ipcRenderer.on 'scroll-touch-end', ->
  window.dispatchEvent(new Event('scroll-touch-end'))

class Delete extends React.Component
  render: ->
    <svg fill="#FFFFFF" height="24" viewBox="0 0 24 24" width="24" xmlns="http://www.w3.org/2000/svg">
      <path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/>
      <path d="M0 0h24v24H0z" fill="none"/>
    </svg>

class Archive extends React.Component
  render: ->
    <svg fill="#FFFFFF" height="24" viewBox="0 0 24 24" width="24" xmlns="http://www.w3.org/2000/svg">
        <path d="M20.54 5.23l-1.39-1.68C18.88 3.21 18.47 3 18 3H6c-.47 0-.88.21-1.16.55L3.46 5.23C3.17 5.57 3 6.02 3 6.5V19c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V6.5c0-.48-.17-.93-.46-1.27zM12 17.5L6.5 12H10v-2h4v2h3.5L12 17.5zM5.12 5l.81-1h12l.94 1H5.12z"/>
        <path d="M0 0h24v24H0z" fill="none"/>
    </svg>

class Snooze extends React.Component
  render: ->
    <svg fill="#FFFFFF" height="24" viewBox="0 0 24 24" width="24" xmlns="http://www.w3.org/2000/svg">
        <path d="M0 0h24v24H0z" fill="none"/>
        <path d="M22 5.72l-4.6-3.86-1.29 1.53 4.6 3.86L22 5.72zM7.88 3.39L6.6 1.86 2 5.71l1.29 1.53 4.59-3.85zM12.5 8H11v6l4.75 2.85.75-1.23-4-2.37V8zM12 4c-4.97 0-9 4.03-9 9s4.02 9 9 9c4.97 0 9-4.03 9-9s-4.03-9-9-9zm0 16c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z"/>
    </svg>

class List extends React.Component
  render: ->
    <svg fill="#FFFFFF" height="24" viewBox="0 0 24 24" width="24" xmlns="http://www.w3.org/2000/svg">
        <path d="M3 13h2v-2H3v2zm0 4h2v-2H3v2zm0-8h2V7H3v2zm4 4h14v-2H7v2zm0 4h14v-2H7v2zM7 7v2h14V7H7z"/>
        <path d="M0 0h24v24H0z" fill="none"/>
    </svg>

defaultActions = ['', 'delete', 'archive', 'snooze', 'list']

trashActions = ['', 'expunge', 'archive', 'mailbox', 'snooze']

# TODO: in other & trash should lsit be doable?? does mailbox allow to be in folder and inbox?

actions = {
  1: defaultActions
  2: []
  3: []
  4: trashActions
  5: defaultActions
}

MorphIcon = React.createClass
  displayName: 'MorphIcon'
  shouldComponentUpdate: (nextProps) ->
    @props.action isnt nextProps.action
  render: ->
    <MorphReplace width={25} height={25} rotation={if (@props.direction and @props.action is 2) or (not @props.direction and @props.action is 3) then 'clockwise' else 'counterclock'}>
      {
        if @props.action is 1
          <Delete key="delete" />
        else if @props.action is 2
          <Archive key="archive" />
        else if @props.action is 3
          <Snooze key="snooze" />
        else if @props.action is 4
          <List key="list" />
      }
    </MorphReplace>

# TODO touch support

# TODO: ISSUE. Swipe being carried over to next element....
VELOCITY_CONST = 0.03
Swipe = React.createClass
  displayName: 'Swipe'
  getInitialState: ->
    instantActivate: false
    settling: false
    position: 0
    activated: false
    action: 0
    startedAt: 0
    deltaX: 0
    acted: false
    controlling: false
  componentDidMount: ->
    SwipeController.addListener(@runState)
    window.addEventListener 'scroll-touch-begin', @onScrollTouchBegin
    window.addEventListener 'scroll-touch-end', @onScrollTouchEnd
  componentWillUnmount: ->
    window.removeEventListener 'scroll-touch-begin', @onScrollTouchBegin
    window.removeEventListener 'scroll-touch-end', @onScrollTouchEnd
    SwipeController.removeListener(@runState)
  componentDidUpdate: ->
    window.requestAnimationFrame(@settle) if @state.settling and @state.position isnt 0
  runState: (pos, type) ->
    # { position, activated, action, settling, deltaX }
    # TODO: instead just send state and we can update it globally.
    if type is 'RESET' and @state.action > 0
      @setState(action: 0)
      dynamics.animate(ReactDOM.findDOMNode(@refs.swipe), {
        translateX: 0
      }, {
        type: dynamics.spring
        complete: =>
          @reset()
      })
      return
    @onWheel(false, { deltaX: pos, deltaY: 0 }) if @props.selected
  onScrollTouchBegin: ->
    @setState(settling: false, startedAt: new Date().getTime()) if not @state.settling
  onScrollTouchEnd: ->
    if not @state.settling and @state.position isnt 0
      action = @state.action
      @setState({ settling: true, startedAt: 0, action })
  settle: ->
    return if @state.acted
    # TODO: make type check global prop so it isn't recalculated
    if @state.activated and Store.global.state.folder?.type not in [2, 3]
      if Math.abs(@state.position) <= @props.clientWidth
        position = @state.position + ((if @state.position >= 0 then 1 else -1) * (@props.clientWidth * VELOCITY_CONST))
        @setState({ position })
      else if @state.position > 0
        if @state.action is 1
          @setState({ acted: true })
          @props.delete(@props.selected) if @state.controlling
      else if @state.position < 0
        if @state.action is 1
          @setState({ acted: true })
          if @state.controlling
            Store.actions.dispatch('popover', ['snooze', 'right', ReactDOM.findDOMNode(@refs['swipe-container']).getBoundingClientRect(), =>
              SwipeController.setPosition(0, 'RESET')
            , (snoozedTo) =>
              @props.snooze(@props.selection, snoozedTo)
              Store.actions.dispatch('popover', ['snooze', 'right'])
            ])
          # TODO: handle opposite side interactions
    else
      # TODO: if touch-down which aniamtion finishing, need to transition gracefully.
      dynamics.animate(ReactDOM.findDOMNode(@refs.swipe), {
        translateX: 0
      }, {
        type: dynamics.spring
        complete: =>
          @reset()
      })
  reset: ->
    @setState({
      instantActivate: false
      settling: false
      position: 0
      activated: false
      action: 0
      startedAt: 0
      acted: false
      controlling: false
    })
  onWheel: (browserEvent, { deltaX, deltaY }) ->
    # TODO make scroll lock.
    return if @state.settling
    SwipeController.setPosition(deltaX) if @props.selected and browserEvent
    offset = deltaX / 3
    offset *= -1 # TODO if inverse
    activated = Math.abs(deltaX) > 3
    instantActivation = Math.abs(deltaX) > 200 and (@state.startedAt - new Date().getTime()) < 100
    # TODO: is the delta activation value ok? and is the time check too much? Shouldn't be easy to reach.
    position = if @state.position < 0
                Math.max(@state.position + offset, -1*@props.clientWidth)
              else
                Math.min(@state.position + offset, @props.clientWidth)
    # TODO: should bcome harder to reach the further you go.
    if @state.instantActivate
      instantActivation = true
      action = @state.action
    else if Store.global.state.folder?.type not in [2, 3]
      if instantActivation
        activated = true
        action = 1
      else
        action = 0
        if Math.abs(position) > @props.clientWidth / 2
          action = 2
        else if Math.abs(position) > @props.clientWidth / 6
          action = 1
    # TODO increase inactive space
    settling = if Math.abs(@props.clientWidth) is position or instantActivation then true else false # TODO: should clientWidth trigger this?
    controlling = false
    if @props.selected
      controlling = true if browserEvent
    else
      controlling = true
    if @state.activated
      activated = @state.activated
    if not action? or action is 0
      activated = false
    @setState({ instantActivate: instantActivation, position, activated, action, settling, deltaX, controlling })
  render: ->
    action = @state.action + (if @state.position < 0 and @state.action isnt 0 then 2 else 0)
    <div onWheel={(obj) => @onWheel(true, obj)} className="swipe #{actions[Store.global.state.folder?.type]?[action] ? ''} #{if @state.position isnt 0 then 'swiping' else ''}" style={transform: "translate3d(0, #{@props.index * 90}px, 0)"} ref="swipe-container">
      {
        if @state.action > 0
          <div className="action-icon #{if @state.acted then 'fadehide' else ''}" style={transform: "translate3d(#{if @state.position < 0 then @state.position+300+35 else @state.position-(35+25)}px, 0, 0)"}>
            <MorphIcon direction={@state.position > 0} action={action} />
          </div>
      }
      <div style={transform: "translate3d(#{@state.position}px, 0, 0)"} ref="swipe">
        {@props.children}
      </div>
    </div>

module.exports = Swipe
