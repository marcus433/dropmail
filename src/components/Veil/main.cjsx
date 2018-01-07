require './_main.scss'
React = require 'react'
Store = require '../../store'

Veil = React.createClass
  displayName: "Veil"
  getInitialState: =>
    show: false
    popover: false
  componentDidMount: ->
    window.addEventListener('blur', @onBlur)
    window.addEventListener('focus', @onFocus)
    Store.actions.addListener('popover', @forceShow)
  componentDidUnmount: ->
    window.removeEventListener('blur', @onBlur)
    window.removeEventListener('focus', @onFocus)
    Store.actions.removeListener('popover', @forceShow)
  onBlur: ->
    setTimeout =>
      if document.activeElement.tagName isnt 'IFRAME'
        @setState show: true
      else
        window.focus()
    , 1
  onFocus: ->
    @setState show: false
  forceShow: (type, orientation, boundingBox) ->
    @setState(popover: if boundingBox? then true else false)
  hidePopover: ->
    Store.actions.dispatch('popover', [null, null, null])
    @setState(popover: false)
  render: ->
    <div className="veil#{if @state.show then ' show' else ''}#{if @state.popover then ' popoverstate' else ''}" onClick={@hidePopover}></div>

module.exports = Veil
