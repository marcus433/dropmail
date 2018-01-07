var { app, BrowserWindow, ipcMain, dialog, nativeImage } = require('electron');
var { moveToApplications } = require('electron-lets-move');

var pool = {};

app.commandLine.appendSwitch('disable-renderer-backgrounding');
app.commandLine.appendSwitch('ignore-certificate-errors');
//app.commandLine.appendSwitch('disable-http-cache');

//app.commandLine.appendSwitch('js-flags', '--trace-gc --gc-global --noincremental-marking --max-executable-size=192 --max-old-space-size=256 --max-semi-space-size=2'); // --expose-gc
// --trace-gc --gc-global --noincremental-marking --max-executable-size=192 --max-old-space-size=256 --max-semi-space-size=2'
// require('electron').remote.getCurrentWindow().webContents.session.clearCache(() => {console.log('done');});
//require('electron').webFrame.clearCache()
app.on('window-all-closed', function() {
  if (process.platform !== 'darwin')
    app.quit();
});

app.on('ready', function() {
  /*
  moveToApplications(function (err, moved) {
    if (err) {
      console.log(err);
    }
    if (!moved) {
      console.log('todo: db magic');
    }
  });*/
});

app.on('ready', function() {
  var workerWindow = new BrowserWindow({ width: 500, height: 350, title: "Sync Worker", neverClose: true, show: false, "always-on-top": true });
  workerWindow.toggleDevTools();
  ipcMain.on('IMAPWorker', (event, tag, accountId, folderId, target, req) => {
  	workerWindow.webContents.send('IMAPWorker', tag, accountId, folderId, target, req);
  	pool[tag] = (tag, resp) => {
  		event.sender.send('IMAPReciever', tag, resp);
  	};
  });
  ipcMain.on('IMAPListener', (event, changes) => {
    var windows = BrowserWindow.getAllWindows();
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] !== workerWindow) {
        windows[i].webContents.send('IMAPListener', changes);
      }
    }
  });
  ipcMain.on('IMAPReciever', (event, tag, resp) => {
  	pool[tag].apply(pool[tag], [tag, resp]);
  	delete pool[tag];
  });
  ipcMain.on('addAccount', (event, options) => {
    workerWindow.webContents.send('addAccount', options);
  });
  ipcMain.on('addAccountStatus', (event, status) => {
    var windows = BrowserWindow.getAllWindows();
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] !== workerWindow) {
        windows[i].webContents.send('addAccountStatus', status);
      }
    }
  });
  workerWindow.loadURL('file://' + __dirname + '/worker.html');
});
