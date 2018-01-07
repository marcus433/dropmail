require 'workspace.scss'
React = require 'react'
ReactDOM = require 'react-dom'
Compose = require 'components/Compose/Main'

ReactDOM.render <div className="wrapper">
                  <Compose></Compose>
                </div>, document.querySelector('dropmail-workspace')
