require 'workspace.scss'
React = require 'react'
ReactDOM = require 'react-dom'
OnboardingView = require 'components/OnboardingView/main'
Veil = require 'components/Veil/Main'

ReactDOM.render <div className="wrapper">
                  <div className="interface dark-ui column">
                    <OnboardingView></OnboardingView>
                  </div>
                  <Veil />
                </div>, document.querySelector('dropmail-workspace')
