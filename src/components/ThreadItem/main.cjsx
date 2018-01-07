require './_main.scss'
React = require 'react'
ReactDOM = require 'react-dom'
SwipeContainer = require '../SwipeContainer/main'
TimeNotation = require '../../utils/time-notation'
{ selections, collections, global } = require '../../store'
realm = require '../../api/realm'
{ remote: { app } } = require 'electron'
AVATAR_PATH = app.getPath('userData')+'/avatars/'

i = 0
tags = ['social', 'personal', 'service', 'newsletter']
ThreadItem = React.createClass
  displayName: "ThreadItem"
  shouldComponentUpdate: (props, state) ->
    @props.selected isnt props.selected or
    @props.index isnt props.index or
    @props.item.cached isnt props.item.cached or
    props.item.toSelf isnt @props.item.toSelf or
    props.item.unread isnt @props.item.unread or
    props.item.count isnt @props.item.count or
    props.item.timestamp isnt @props.item.timestamp or
    props.item.name isnt @props.item.name or
    props.item.address isnt @props.item.address or
    props.item.tag isnt @props.item.tag
  onClick: ->
    if selections.meta and not selections.shift
      selections.toggleSelect(@props.index)
    else if selections.shift and not selections.meta
      selections.multiselect(@props.index)
    else
      selections.selectOne(@props.index)
    ###
    TODO walkMultiSelect
    ###
  delete: (selection) ->
    # TODO: preserve/lock focus and ranges momentrily
    conversations = []
    if selection
      for [start, end] in selections.ranges
        conversations = conversations.concat(collections.focus[start..end])
    else
      conversations.push(collections.focus[@props.index])
    realm.write =>
      # TODO; multiple account support
      realm.create('Outbox', {
        account: global.state.accounts[0]
        type: 1
        target: 1
        initialState: 'INBOX'
        targetState: '[Gmail]/Trash'
        timestamp: new Date()
        conversations
      })
  snooze: (selection, snoozedTo) ->
    # TODO: preserve/lock focus and ranges momentrily
    conversations = []
    if selection
      for [start, end] in selections.ranges
        conversations = conversations.concat(collections.focus[start..end])
    else
      conversations.push(collections.focus[@props.index])
    realm.write =>
      realm.create('Outbox', {
        account: global.state.accounts[0]
        type: 4
        target: 1
        targetState: snoozedTo
        timestamp: new Date()
        conversations
      })
  render: ->
    tag = tags[@props.item.tag] or 'newsletter'
    visibility = if not @props.item.unread then 'none' else 'inline-block'
    <SwipeContainer delete={@delete} snooze={@snooze} clientWidth={300} threshold={110} index={@props.index} selected={@props.selected}>
      <li onClick={@onClick} className="ThreadItem#{if @props.selected then ' selected' else ''}" draggable="true">
        <div className="tag #{tag}"></div>
        <div className="avatar #{if not @props.item.cached then tag else ''}" style={background:if @props.item.cached then "url('#{AVATAR_PATH + @props.item.addressHash}') no-repeat" else ''}>
          { if not @props.item.cached then (@props.item.name[0] or @props.item.address[0]).toUpperCase() else '' }
        </div>
        <div className="group">
          <div className="participantOverview #{tag}">
            {
              ##{ if not @props.item.name or @props.item.name.length is 0 then names.addressToName(1, @props.item.address) else @props.item.name }
              # TODO: handle ME
              if @props.item.toSelf
                'Note to self'
              else
                @props.item.name
            }
          </div>
          <div className="subject">
            {if @props.item.subject.length is 0 then '(no subject)' else @props.item.subject}
          </div>
        </div>
        {
          count = @props.item.count
          <div className="count">{if count > 1 then count else ''}</div>
        }
        <div className="date">
          <iron-icon icon="alarm" style={display:if @props.item.snoozed then 'inline-block' else 'none'}></iron-icon>
          <iron-icon icon="attachment" style={display:if @props.item.hasFiles then 'inline-block' else 'none'}></iron-icon>
          <iron-icon icon="visibility" style={display:visibility}></iron-icon>
          { new TimeNotation(@props.item.timestamp).state() }
        </div>
      </li>
    </SwipeContainer>

module.exports = ThreadItem
