require './_main.scss'
React = require 'react'
ReactDOM = require 'react-dom'
realm = require '../../api/realm'

###
general
  - default client
  - notifications
    - only personal
    - for new
    - for snoozed
  - Badge COUNT
    - Show Unread conversation COUNT
    - Show "1" for new messages
    - Don't show
  - Mark swipes as Read
  - user avatars
  - On-click unsubscribe (unsubscribe, unsubscribe & trash, unsubscribe & archive)
accounts
  - default
  - add account
  - use same signature across accounts?
  - account
    - name
    - address
    - description
    - signature
    - aliases
    - choose archive folder
Swipes
  - customize swipes
Snooze
  - Start day
  - Start weekend
  - End Workday
  - Week starts
  - Later today gap
  - someday gap
###

PreferenceItem = React.createClass
  displayName: "PreferenceItem"
  getInitialState: ->
  componentDidMount: ->
  render: ->
    <div className="preferenceItem">
    </div>

Preferences = React.createClass
  displayName: "Preferences"
  getInitialState: ->
  componentDidMount: ->
  render: ->
    <div className="preferences">
    </div>

module.exports = Compose
