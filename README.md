
# lite-xl-terminal

### Note: This plugin can only be compiled and used on a Linux system for now, Windows compatibility will hopefully come soon™ (maybe)

A plugin to add a terminal window to lite-xl with access to your system shell.

![demo screenshot](/assets/screenshot.png)

## Building and Installation

You need to have make and GCC installed on your machine for building the plugin.

- Clone the repository and build the plugin by running the following commands:
```bash 
git clone --recursive https://github.com/benjcollins/lite-xl-terminal.git
cd lite-xl-terminal
make
```
- make a folder called `lite-xl-terminal` in `~/.config/lite-xl/plugins/`, and add init.luw and the compiled terminal executable into it.
- restart lite-xl, and open the terminal window by pressing `Ctrl+t`. The terminal should ope in the bottom half of the main window.
