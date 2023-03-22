# notes2html
Back up Apple Notes to HTML or PDF files

## Getting Started

To install, clone the repository:

```
git clone https://github.com/forbes3100/notes2html.git
```

## Usage

Double-click notes2html.applescript which should open in the Script Editor. Either run it there by clicking the start button, or save it as a stand-alone application.

When run it will create the folder notes_icloud_bak in Documents if it doesn't exist, and write each note to a .html file there in subfolders matching the folder hierarchy in Notes. The file names have spaces changed to underscores to ease use with Unix.

When run again only updated notes will be written.

To change it to write PDF files, open the file in the Script Editor and change the "set writePdf to" line to "true". Note that PDF exporting from Notes requires adding the Script Editor to the list of applications in System Preferences>Privacy & Security>Accessibility, which can be a security risk.
