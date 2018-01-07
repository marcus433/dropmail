require 'workspace.scss'
React = require 'react'
ReactDOM = require 'react-dom'

Navigation = require 'components/Navigation/main'
ScrollView = require 'components/ScrollView/main'
DownloadsView = require 'components/DownloadsView/main'
ConversationView = require 'components/ConversationView/main'
Popover = require 'components/Popover/main'
Veil = require 'components/Veil/Main'

ReactDOM.render <div className="wrapper">
                  {
                    if process.platform isnt 'darwin'
                      <div className="window-controls-container">dropmail</div>
                  }
                  <div className="interface dark-ui">
                    <Navigation />
                    <ScrollView itemHeight={90}></ScrollView>
                    <ConversationView />
                    <DownloadsView />
                    <Popover />
                  </div>
                  <Veil />
                </div>, document.querySelector('dropmail-workspace')
