var webpack = require('webpack');
var path = require('path');
var ExtractTextPlugin = require('extract-text-webpack-plugin');
var StatsPlugin = require('stats-webpack-plugin');
var loadersByExtension = require('loaders-by-extension');
var webpackTargetElectronRenderer = require('webpack-target-electron-renderer');

var projectRoot = path.join(__dirname, '../..');
var appRoot = path.join(projectRoot, 'src');

module.exports = function(opts) {
  var entry = {
    'main': path.join(appRoot, 'workspace.cjsx'),
    'onboarding': path.join(appRoot, 'onboarding.cjsx'),
    'compose': path.join(appRoot, 'compose.cjsx')
  };
  var loaders = {
    'jsx': opts.hotComponents ? [ 'react-hot-loader/webpack'] : [],
    'cjsx': opts.hotComponents ? [ 'react-hot-loader/webpack', 'coffee-loader', 'cjsx-loader'] : ['coffee-loader', 'cjsx-loader'],
    'coffee': {
      loader: 'coffee-loader',
      include: appRoot
    },
    'json': 'json-loader',
    'png|jpg|jpeg|gif|svg': 'url-loader?limit=10000',
    'woff|woff2': 'url-loader?limit=100000',
    'ttf|eot|otf': 'file-loader',
    'wav|mp3': 'file-loader',
    'html': 'html-loader'
  };

  var cssLoader = opts.minimize ? 'css-loader' : 'css-loader?localIdentName=[path][name]---[local]---[hash:base64:5]';

  var stylesheetLoaders = {
    'css': cssLoader,
    'scss|sass': [ cssLoader, 'sass-loader']
  };

  var alias = {

  };

  var aliasLoader = {

  };

  // they reference a native node module thus we can't mess w/ them
  var externals = [
    'sqlite3',
    'realm',
    'knex',
    'vertx',
    'emailjs-imap-client',
    'node-mac-notifier',
    'fs',
    'keytar',
    'url',
    'http'
  ];
  // TODO emailjs-imap-client shouldn't be external
  /*if (opts.debug)
    externals.push(/^[a-z\/\-0-9]+$/i);*/
  // NOTE: for production builds find solutions to resolve the mpdule expression conflicts

  var modulesDirectories = [ 'node_modules' ];

  var extensions = [ '', '.js', '.jsx', '.cjsx', '.coffee', '.json', '.node', '.scss' ];

  var publicPath = opts.devServer
                 ? 'http://localhost:2992/dist/'
                 : '/dist/';

  var output = {
    path: projectRoot + '/dist/',
    filename: '[name].bundle.js',
    chunkFilename: "[id].chunk.js",
    publicPath: publicPath,
    contentBase: projectRoot + '/public/',
    libraryTarget: 'commonjs2'
  };

  var excludeFromStats = [
    /node_modules[\\\/]react(-router)?[\\\/]/
  ];

  /*
  new webpack.optimize.CommonsChunkPlugin("database", "database.bundle.js"),
  new webpack.optimize.CommonsChunkPlugin("compose", "compose.bundle.js")
  */
  var plugins = [
    new webpack.PrefetchPlugin('react'),
    new webpack.PrefetchPlugin('react/lib/ReactComponentBrowserEnvironment'),
    new webpack.optimize.CommonsChunkPlugin({ filename: "commons.js", name: "commons" }),
  ];

  if (opts.prerender) {
    plugins.push(new StatsPlugin(path.join(projectRoot, 'dist', 'stats.prerender.json'), {
      chunkModules: true,
      exclude: excludeFromStats
    }));
    aliasLoader['react-proxy$'] = 'react-proxy/unavailable';
    aliasLoader['react-proxy-loader$'] = 'react-proxy-loader/unavailable';
    externals.push(
      /^react(\/.*)?$/,
      /^reflux(\/.*)?$/,
      'superagent',
      'async',
      'sqlite3',
      'knex',
      'realm',
      'node-mac-notifier',
      'fs'
    );
    //plugins.push(new webpack.optimize.LimitChunkCountPlugin({ maxChunks: 1 }));
  } else {
    plugins.push(new StatsPlugin(path.join(projectRoot, 'dist', 'stats.json'), {
      chunkModules: true,
      exclude: excludeFromStats
    }));
  }

  if (opts.commonsChunk) {
    plugins.push(new webpack.optimize.CommonsChunkPlugin('commons', 'commons.js' + (opts.longTermCaching && !opts.prerender ? '?[chunkhash]' : '')));
  }

  Object.keys(stylesheetLoaders).forEach(function(ext) {
    var stylesheetLoader = stylesheetLoaders[ext];
    if (Array.isArray(stylesheetLoader)) stylesheetLoader = stylesheetLoader.join('!');
    if (opts.prerender) {
      stylesheetLoaders[ext] = stylesheetLoader.replace(/^css-loader/, 'css-loader/locals');
    } else if (opts.separateStylesheet) {
      stylesheetLoaders[ext] = ExtractTextPlugin.extract('style-loader', stylesheetLoader);
    } else {
      stylesheetLoaders[ext] = 'style-loader!' + stylesheetLoader;
    }
  });

  if (opts.separateStylesheet && !opts.prerender) {
    plugins.push(new ExtractTextPlugin('[name].css' + (opts.longTermCaching ? '?[contenthash]' : '')));
  }

  if (opts.minimize && !opts.prerender) {
    plugins.push(
      new webpack.optimize.UglifyJsPlugin({
        compressor: {
          warnings: false
        }
      }),
      new webpack.optimize.DedupePlugin()
    );
  }

  if (opts.minimize) {
    plugins.push(
      new webpack.DefinePlugin({
        'process.env': {
          NODE_ENV: "'production'"
        }
      }),
      new webpack.NoErrorsPlugin()
    );
  }

  var options = {
    entry: entry,
    output: output,
    externals: externals,
    module: {
      loaders: loadersByExtension(loaders).concat(loadersByExtension(stylesheetLoaders))
    },
    devtool: opts.devtool,
    debug: opts.debug,
    resolve: {
      root: appRoot,
      modulesDirectories: modulesDirectories,
      extensions: extensions,
      alias: alias,
      packageMains: ['webpack', 'browser', 'web', 'browserify', ['jam', 'main'], 'main']
    },
    plugins: plugins,
    devServer: {
      stats: {
        cached: false,
        exclude: excludeFromStats
      }
    }
  };

  options.target = webpackTargetElectronRenderer(options);

  return options;
};
