
# lite-xl-terminal
A plugin to add a terminal window to lite-xl with access to your system shell.

![demo screenshot](screenshot.png)

## Building and Installation

#### Common prerequisites
You need to have make and GCC installed on your machine for building the plugin.
> On Windows you'll need [winpty][1] and you can install it with `pacman` (MSYS2) or download it from their website. On the other hand, you could try [winpty-wrapper][2] which uses [ConPTY][3] instead.

Clone the repository in the config folder and build the plugin by running the following commands:
```bash 
cd ~/.config/lite-xl/plugins
git clone --recursive https://github.com/benjcollins/lite-xl-terminal.git
cd lite-xl-terminal
make release
```
> On Windows, you'll need to copy `winpty.dll` and `winpty-agent.exe` to the same folder.

> If you compile on MSYS2 and installed winpty via `pacman`, you'll need to run `CFLAGS="-I/usr/include -L/usr/lib" make release` because the library is actually installed in `/usr` instead of `/mingw{32,64}`

#### Usage
Open the terminal window by pressing `Ctrl+t`. The terminal should open in the bottom half of the main window.


[1]: https://github.com/rprichard/winpty
[2]: https://github.com/takase1121/winpty-wrapper
[3]: https://devblogs.microsoft.com/commandline/windows-command-line-introducing-the-windows-pseudo-console-conpty/
