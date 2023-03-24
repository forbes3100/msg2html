# macbak
iCloud backup via a Mac, with optional source control


## Introduction

macbak is a collection of tools for providing an independent backup and
optional source control for Apple iCloud based resources. These work by
converting each resource to HTML and copying it to your Mac for both
safekeeping and as a way to allow line-based source control such as git if
desired. The icdrivebak tool doesn't convert but forces all iCloud Drive files
to be copied to the Mac. Together these allow normal Mac backup of these files.

Tools:

- msg2html -- Convert Mac Messages database into HTML
- notes2html -- Back up Apple Notes to HTML or PDF files
- icdrivebak -- Force all iCloud Drive files to be downloaded, for backup


## Getting Started

To install, first clone the repository:

```
git clone https://github.com/forbes3100/macbak.git
cd macbak
```

Then install dependencies:

```
pip3 install coverage pyemoji pillow_heif ui
```

## Running the tests

The following command should run all tests, ending with "OK".

```
./test_msg2html.py
```

## Usage

# msg2html

Copy your chat.db file and Attachments folder from your library into the macbak working directory:

In Finder, hold down Option and choose Go > Library. Open the Messages folder there, select both chat.db and the Attachments folder, and type Cmd-C to copy. Then navigate to your macbak folder and type Cmd-V.

The program requires the file chat_handles.json, a list of phone-numbers/email and corresponding full names in JSON format, in the macbak folder. e.g.:

```
{
"+15555551212": "John Doe",
"jane.doe@example.com": "Jane Doe"
}
```

To convert one year, e.g. 2022, type:

```
./msg2html.py 2022
```

It should generate the file 2022.html, which may include links to image files in Attachments there. That file can then be opened in your browser.

```
open 2022.html
```

It can also convert a range of years, generating one file per year. E.g.:

```
./msg2html.py 2012 2022
```

If some attachments have gone missing from the Attachments folder (typically because they're old), they may be restored from a backup copy using the "-e path" switch. For example if old images from 2018 are found in a Time Machine backup dated "2020-02-10-203611" on drive "TM1" (e.g., by using "sudo find Backups.backupdb -type f -ls"), they may be incorporated by typing something like:

```
sudo ./msg2html.py 2018 -e /Volumes/TM1/Backups.backupdb/MyMac/2020-02-10-203611/Drive/Users/jd/Library/Messages/Attachments
```

Sudo will be needed if the permissions of the backup differ. You can search for "Copying to" in the HTML output to see where each attachment that was found was copied to. Also be sure to fix the permissions of the files afterward using (substituting your login name):

```
sudo chown -R yourname Attachments
```

For ease in extracting image files, the "-f" switch tells it to generate a "links" folder of soft-links to those image files within the Attachments folder. It always adds new links (appending sequence numbers to file names as needed), so delete any existing links folder beforehand.

```
./msg2html.py 2022 -f
```

# notes2html

Double-click notes2html.applescript which should open in the Script Editor. Either run it there by clicking the start button, or save it as a stand-alone application.

When run it will create the folder notes_icloud_bak in Documents if it doesn't exist, and write each note to a .html file there in subfolders matching the folder hierarchy in Notes. The file names have spaces changed to underscores to ease use with Unix.

When run again only updated notes will be written.

To change it to write PDF files, open the file in the Script Editor and change the "set writePdf to" line to "true". Note that PDF exporting from Notes requires adding the Script Editor to the list of applications in System Preferences>Privacy & Security>Accessibility, which can be a security risk.


# icdrivebak



## Contributing

Please read [CONTRIBUTING.md](https://github.com/forbes3100/macbak.git/blob/master/CONTRIBUTING.md) for details on our code of conduct, and the process for submitting pull requests to us.

## Authors

* **Scott Forbes** - *Initial work* - [forbes3100](https://github.com/forbes3100)

See also the list of [contributors](https://github.com/forbes3100/macbak.git/graphs/contributors) who participated in this project.

## License

This project is licensed under the GNU General Public License.
