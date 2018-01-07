var electron = require('electron'),
    { BrowserWindow, Menu, app, dialog } = electron.remote,
    { ipcRenderer } = electron,
    menu,
    template,
    mainWindow = null;

var SyncEngine = require('../dist/engine');

//'title-bar-style': 'hidden'
//compose: 552h x 751w
//main: 1287x800

var engine = new SyncEngine();

var onIMAPRequest = (event, tag, accountId, folderId, target, req) => {
  // TODO: remove need for folderId at all.
  var backend = engine.accounts[accountId].backends['ACTION_CLIENT'];
  if (typeof backend === "undefined" || backend === null) {
    ipcRenderer.send('IMAPReciever', tag, { success: false, error: 'Backend doesn\'t exist.' });
    return;
  }
  backend[target].apply(backend, req)
  .then((...results) => {
    ipcRenderer.send('IMAPReciever', tag, { success: true, results: results });
  })
  .catch((err) => {
    if (typeof err === "undefined" || err === null) {
      err = "";
    }
    ipcRenderer.send('IMAPReciever', tag, { success: false, error: err.toString() });
  });
};

function mainWindowReset(win) {
  win.on('ready-to-show', () => {
    win.show();
  });

  win.on('scroll-touch-begin', function () {
    win.webContents.send('scroll-touch-begin');
  });

  win.on('scroll-touch-end', function () {
    win.webContents.send('scroll-touch-end');
  });

  /*if (process.env.NODE_ENV === 'development') {
    mainWindow.openDevTools();
  }*/
  if (process.platform === 'darwin') {
    template = [{
      label: 'DropMail',
      submenu: [{
        label: 'About DropMail',
        selector: 'orderFrontStandardAboutPanel:'
      }, {
        type: 'separator'
      }, {
        label: 'Services',
        submenu: []
      }, {
        type: 'separator'
      }, {
        label: 'Hide DropMail',
        accelerator: 'Command+H',
        selector: 'hide:'
      }, {
        label: 'Hide Others',
        accelerator: 'Command+Shift+H',
        selector: 'hideOtherApplications:'
      }, {
        label: 'Show All',
        selector: 'unhideAllApplications:'
      }, {
        type: 'separator'
      }, {
        label: 'Quit',
        accelerator: 'Command+Q',
        click: function() {
          app.quit();
        }
      }]
    }, {
      label: 'Edit',
      submenu: [{
        label: 'Undo',
        accelerator: 'Command+Z',
        selector: 'undo:'
      }, {
        label: 'Redo',
        accelerator: 'Shift+Command+Z',
        selector: 'redo:'
      }, {
        type: 'separator'
      }, {
        label: 'Cut',
        accelerator: 'Command+X',
        selector: 'cut:'
      }, {
        label: 'Copy',
        accelerator: 'Command+C',
        selector: 'copy:'
      }, {
        label: 'Paste',
        accelerator: 'Command+V',
        selector: 'paste:'
      }, {
        label: 'Select All',
        accelerator: 'Command+A',
        selector: 'selectAll:'
      }]
    }, {
      label: 'View',
      submenu: [{
        label: 'Reload',
        accelerator: 'Command+R',
        click: function() {
          win.restart();
        }
      }, {
        label: 'Toggle Developer Tools',
        accelerator: 'Alt+Command+I',
        click: function() {
          win.toggleDevTools();
        }
      }, {
        label: 'Toggle Full Screen',
        accelerator: 'Ctrl+Command+F',
        click: function() {
          win.setFullScreen(!win.isFullScreen());
        }
      }]
    }, {
      label: 'Window',
      submenu: [{
        label: 'Minimize',
        accelerator: 'Command+M',
        selector: 'performMiniaturize:'
      }, {
        label: 'Close',
        accelerator: 'Command+W',
        selector: 'performClose:'
      }, {
        type: 'separator'
      }, {
        label: 'Bring All to Front',
        selector: 'arrangeInFront:'
      }]
    }, {
      label: 'Help',
      submenu: [{
        label: 'Learn More',
        click: function() {
          electron.shell.openExternal('http://dropmailapp.com');
        }
      }]
    }];

    menu = Menu.buildFromTemplate(template);
    Menu.setApplicationMenu(menu);
  } else {
    template = [{
      label: '&File',
      submenu: [{
        label: '&Open',
        accelerator: 'Ctrl+O'
      }, {
        label: '&Close',
        accelerator: 'Ctrl+W',
        click: function() {
          win.close();
        }
      }]
    }, {
      label: '&View',
      submenu: [{
        label: '&Reload',
        accelerator: 'Ctrl+R',
        click: function() {
          win.restart();
        }
      }, {
        label: 'Toggle &Full Screen',
        accelerator: 'F11',
        click: function() {
          win.setFullScreen(!win.isFullScreen());
        }
      }]
    }, {
      label: 'Help',
      submenu: [{
        label: 'Learn More',
        click: function() {
          electron.shell.openExternal('http://dropmailapp.com');
        }
      }]
    }];
    menu = Menu.buildFromTemplate(template);
    win.setMenu(menu);
  }
}

var addAccount = (event, options) => {
  engine.addAccount(options).then((resp) => {
    if (resp.success === true) {
      mainWindow.close();
      mainWindow = new BrowserWindow({ show: true, width: 1287, height: 800, frame: false, backgroundColor:'#1E1E1E' });
      if (process.env.HOT) {
        mainWindow.loadURL('file://' + __dirname + '/index-hot-load.html');
      } else {
        mainWindow.loadURL('file://' + __dirname + '/index.html');
      }
      mainWindowReset(mainWindow);
    } else {
      ipcRenderer.send('addAccountStatus', resp);
    }
  }).catch((err) => {
    if (typeof err === "undefined" || err === null) {
      err = "";
    }
    ipcRenderer.send('addAccountStatus', { success: false, error: err.toString() });
  });
};

ipcRenderer.on('IMAPWorker', onIMAPRequest);
ipcRenderer.on('addAccount', addAccount);
var realm = engine.getRealm(),
    accounts = realm.objects('Account');

if (accounts.length > 0) {
  mainWindow = new BrowserWindow({ show: false, width: 1287, height: 800, frame: false, backgroundColor:'#1E1E1E' });
  if (process.env.HOT) {
    mainWindow.loadURL('file://' + __dirname + '/index-hot-load.html');
  } else {
    mainWindow.loadURL('file://' + __dirname + '/index.html');
  }
  //mainWindow.setVibrancy('dark');
} else {
  mainWindow = new BrowserWindow({ show: false, width: 671, height: 434, frame: false, backgroundColor:'#1E1E1E' });
  if (process.env.HOT) {
    mainWindow.loadURL('file://' + __dirname + '/index-hot-load.html?onboarding');
  } else {
    mainWindow.loadURL('file://' + __dirname + '/index.html?onboarding');
  }
}
mainWindowReset(mainWindow);
