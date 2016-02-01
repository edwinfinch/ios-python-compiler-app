# pythoncompiler-ios
Server-dependent Python compiler for iOS

Made for my computer engineering 4U class, this iOS app connects to the server that you will have to setup (find instructions on that <a href="https://github.com/edwinfinch/pythoncompiler-server">here on the server repository</a>).

<h2>Setup</h2>

Setup is easy!

<h3>Requirements</h3>
You must have for this project:
<ul>
  <li><a href="https://developer.apple.com/xcode/">XCode</a></li>
  <li><a href="http://evansheline.com/wp-content/uploads/2012/04/happy-dog.jpg">A smile on your face</a></li>
</ul>

Once you have XCode setup, copy this project's contents anywhere you like. Open `Culminating.xcodeproj` and you're all setup.

<h2>Server Connection</h2>
Because you can't magically connect to a server that doesn't exist, you're gonna have to setup your own. Once you do, you're going to have to modify the server's connection details.

`CFStreamCreatePairWithSocketToHost(NULL, (CFStringRef)@"[SERVER IP]", 5000, &readStream, &writeStream);`

Find this line within `- (void)initNetworkCommunication;` on line ~260 and modify it to include your own server IP and your own port should you change it from 5000 from within `comminication.js` on the server backend.

<h3>Connecting</h3>
Once connected, you should see a message saying `Connected! Please login.` on your iOS device. If so, good work!

<h2>Issues</h2>
Should you have any questions, issues, or comments, please let me know my emailing me: edwin (at) lignite.io.

<h2>Pull Requests and Contributions</h2>
Feel free to make any pull requests and contributions as you wish, and I will review them :)

Enjoy!