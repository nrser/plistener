# plistener

watch OSX plist preference files and record changes.

this is alpha-as-fuck. please use with caution.

it watches preference files stored as `.plist` on OSX and reports changes.

## CLI

### run

run the listener from the terminal, dumping to stdout.
    
    plistener run [options] [working_dir=.]

### clear

remove all the change files in `<working_dir>/changes`.
    
    plistener clear [working_dir=.]


### reset

remove all data in `<working_dir>/data` and change files in `<working_dir>/changes`.

    
    plistener reset [working_dir=.]

