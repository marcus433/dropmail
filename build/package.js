/* eslint no-shadow: 0, func-names: 0, no-unused-vars: 0, no-console: 0 */
var os = require('os');
var webpack = require('webpack');
var cfg = require('./webpack/webpack.config.production.js');
var packager = require('electron-packager');
var assign = require('object-assign');
var del = require('del');
var exec = require('child_process').exec;
var argv = require('minimist')(process.argv.slice(2));
var devDeps = Object.keys(require('../package.json').devDependencies);


var appName = argv.name || argv.n || 'DropMail';
var shouldUseAsar = argv.asar || argv.a || false;
var shouldBuildAll = argv.all || false;


var browserify = require('browserify'),
    coffeeify = require('coffeeify')
    replacestream = require('replacestream'),
    fs = require('fs');


bundle = browserify({
  extensions: ['.coffee'],
  insertGlobals: false,
  detectGlobals: false,
  ignoreMissing: true,
  standalone: 'SyncEngine'
});

bundle.external('knex');
bundle.external('electron');
bundle.external('realm');
bundle.external('fs');
bundle.external('keytar');
bundle.external('node-fetch');
bundle.external('url');
bundle.external('http');
bundle.external('nodemailer');
//bundle.external('emailjs-imap-client');

bundle.transform(coffeeify, {
  bare: false,
  header: true
});

bundle.add('./src/api/sync/engine.coffee');

stream = bundle.bundle();
var writeStream = fs.createWriteStream('./dist/engine.js');
stream.pipe(replacestream('require', 'requireb'))
      .pipe(replacestream("requireb('electron')", "require('electron')"))
      .pipe(replacestream("requireb('realm')", "require('realm')"))
      .pipe(replacestream("requireb('node-mac-notifier')", "require('node-mac-notifier')"))
      .pipe(replacestream("requireb('net')", "require('net')"))
      .pipe(replacestream("requireb('tls')", "require('tls')"))
      .pipe(replacestream("requireb('fs')", "require('fs')"))
      .pipe(replacestream("requireb('keytar')", "require('keytar')"))
      .pipe(replacestream("requireb('node-fetch')", "require('node-fetch')"))
      .pipe(replacestream("requireb('url')", "require('url')"))
      .pipe(replacestream("requireb('http')", "require('http')"))
      .pipe(replacestream("requireb('nodemailer')", "require('nodemailer')"))
      .pipe(writeStream);

/*
var DEFAULT_OPTS = {
  dir: './',
  name: appName,
  asar: shouldUseAsar,
  ignore: [
    '/test($|/)',
    '/tools($|/)',
    '/release($|/)'
  ].concat(devDeps.map(function(name) { return '/node_modules/' + name + '($|/)'; }))
};

var icon = argv.icon || argv.i || '../src/app.icns';

if (icon) {
  DEFAULT_OPTS.icon = icon;
}

var version = argv.version || argv.v || '1.5.0'; // this version must be changed on build

if (version) {
  DEFAULT_OPTS.version = version;
  startPack();
} else {
  // use the same version as the currently-installed electron-prebuilt
  exec('npm list | grep electron', function(err, stdout, stderr) {
    if (err) {
      DEFAULT_OPTS.version = '0.28.3';
    } else {
      DEFAULT_OPTS.version = stdout.split('@')[1].replace(/\s/g, '');
    }
    startPack();
  });
}


function startPack() {
  console.log('start pack...');
  webpack(cfg, function runWebpackBuild(err, stats) {
    if (err) return console.error(err);
    del('release')
    .then(function(paths) {
      if (shouldBuildAll) {
        // build for all platforms
        var archs = ['ia32', 'x64'];
        var platforms = ['linux', 'win32', 'darwin'];

        platforms.forEach(function(plat) {
          archs.forEach(function(arch) {
            pack(plat, arch, log(plat, arch));
          });
        });
      } else {
        // build for current platform only
        pack(os.platform(), os.arch(), log(os.platform(), os.arch()));
      }
    })
    .catch(function(err) {
      console.error(err);
    });
  });
}

function pack(plat, arch, cb) {
  // there is no darwin ia32 electron
  if (plat === 'darwin' && arch === 'ia32') return;

  var opts = assign({}, DEFAULT_OPTS, {
    platform: plat,
    arch: arch,
    out: 'release/' + plat + '-' + arch
  });

  packager(opts, cb);
}


function log(plat, arch) {
  return function(err, filepath) {
    if (err) return console.error(err);
    console.log(plat + '-' + arch + ' finished!');
  };
}*/
