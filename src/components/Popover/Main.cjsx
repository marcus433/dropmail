require './_main.scss'
React = require 'react'
ReactDOM = require 'react-dom'
Store = require '../../store'

Popover = React.createClass
  displayName: 'Popover'
  reject: ->
  resolve: ->
  getInitialState: ->
    hide: true
    top: -500
    left: -500
    height: 325
    width: 325
  componentDidMount: ->
    Store.actions.addListener('popover', @init)
  componentWillUnmount: ->
    Store.actions.removeListener('popover', @init)
  init: (type, orientation, boundingBox, reject, resolve) ->
    if not boundingBox?
      @reject() if @reject?
      @setState(hide: true)
    else
      @reject = reject
      @resolve = resolve
      if orientation is 'right'
        top = boundingBox.top + (boundingBox.height / 2) - (@state.height / 2)
        top = boundingBox.top + (boundingBox.height / 2) if top < 0
        if top + @state.height >= window.innerHeight
          top = window.innerHeight - @state.height - 15
        left = boundingBox.left + boundingBox.width - (@state.width / 2)
        @setState({ top, left, hide: false })
      else if orientation is 'bottom'
        top = boundingBox.top + boundingBox.height + 25
        left = boundingBox.left + (boundingBox.width / 2) - (@state.width / 2)
        @setState({ top, left, hide: false })
  snooze: (type) ->
    console.log 'resolving snooze'
    # TODO types
    # TODO M/ D can be interpreted here too.
    if @resolve?
      @reject = ->
      @resolve(new Date().getTime().toString())
      @setState(hide: true)
    else if @reject?
      @reject()
      @setState(hide: true)
  render: ->
    <div className="popover #{if @state.hide then 'hide' else ''}" style={top: @state.top, left: @state.left} ref="popover">
      <div className="row">
        <div className="item selected" onClick={@snooze}>
          <div className="icon later"></div>
          <div className="label">Later</div>
          <div className="details">2 Hours</div>
        </div>
        <div className="item" onClick={@snooze}>
          <div className="icon evening"></div>
          <div className="label">Evening</div>
          <div className="details">4 PM</div>
        </div>
        <div className="item" onClick={@snooze}>
          <div className="icon tomorrow"></div>
          <div className="label">Tomorrow</div>
          <div className="details">10 AM</div>
        </div>
      </div>
      <div className="row">
        <div className="item" onClick={@snooze}>
          <div className="icon weekend"></div>
          <div className="label">Weekend</div>
          <div className="details">10 AM Saturday</div>
        </div>
        <div className="item" onClick={@snooze}>
          <div className="icon nextweek"></div>
          <div className="label">Next Week</div>
          <div className="details">10 AM Monday</div>
        </div>
        <div className="item" onClick={@snooze}>
          <div className="icon nextmonth"></div>
          <div className="label">Next Month</div>
          <div className="details">4 PM March 6th</div>
        </div>
      </div>
      <div className="row">
        <div className="item" onClick={@snooze}>
          <div className="icon future"></div>
          <div className="label">Future</div>
          <div className="details">9 AM April 10th</div>
        </div>
        <div className="item"></div>
        <div className="item" onClick={@snooze}>
          <div className="icon pickdate"></div>
          <div className="label">Pick Date</div>
          <div className="details">___ __ ______</div>
        </div>
      </div>
    </div>

module.exports = Popover
