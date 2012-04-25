xcodearchive is a command line tool to build and archive your Xcode projects.


xcodearchive will generate an IPA of your project.

xcodearchive can also create an IPA from an App (.app) file.


By default, it saves the dSYM symbols of your project in a ZIP archive (useful for later, when you will want to symbolicate your crash report).
It automatically reads the settings from your Xcode project. You can override some of them, if you need to.


I have only tested it on iPhone projects. If you want to add support for Mac projects, I would be happy to receive a pull request.