# msg2html
Converts a Mac Messages database into HTML

## Getting Started

To install, first clone the repository:

```
git clone https://github.com/forbes3100/msg2html.git
cd msg2html
```

Then install dependencies:

```
pip3 install coverage pyemoji pillow_heif
```

## Running the tests

The following command should run all tests, ending with "OK".

```
./test_msg2html.py
```

## Usage

Copy your chat.db file and Attachments folder from your library into the msg2html working directory:

In Finder, hold down Option and choose Go > Library. Open the Messages folder there, select both chat.db and the Attachments folder, and type Cmd-C to copy. Then navigate to your msg2html folder and type Cmd-V.

The program requires the file chat_handles.json, a list of phone-numbers/email and corresponding full names in JSON format, in the msg2html folder. e.g.:

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

## Contributing

Please read [CONTRIBUTING.md](https://github.com/forbes3100/msg2html.git/blob/master/CONTRIBUTING.md) for details on our code of conduct, and the process for submitting pull requests to us.

## Authors

* **Scott Forbes** - *Initial work* - [forbes3100](https://github.com/forbes3100)

See also the list of [contributors](https://github.com/forbes3100/msg2html.git/graphs/contributors) who participated in this project.

## License

This project is licensed under the GNU General Public License.
