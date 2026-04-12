# Elephant

A service providing various datasources which can be triggered to perform actions.

Run `elephant -h` to get an overview of the available commandline flags and actions.

## Elephant Configuration

`~/.config/elephant/elephant.toml`

#### ElephantConfig

| Field                     | Type                | Default      | Description                                                          |
| ------------------------- | ------------------- | ------------ | -------------------------------------------------------------------- |
| provider_hosts            | map[string][]string |              | providers will only be loaded on the specified hosts. If empty, all. |
| auto_detect_launch_prefix | bool                | true         | automatically detects uwsm, app2unit or systemd-run                  |
| launch_prefix             | string              |              | overrides the default app2unit or uwsm prefix, if set.               |
| terminal_cmd              | string              | <autodetect> | command used to open cmds with terminal                              |
| overload_local_env        | bool                | false        | overloads the local env                                              |
| ignored_providers         | []string            | <empty>      | providers to ignore                                                  |
| git_on_demand             | bool                | true         | sets up git repositories on first query instead of on start          |
| before_load               | []common.Command    |              | commands to run before starting to load the providers                |

#### Command

| Field        | Type   | Default | Description                                                   |
| ------------ | ------ | ------- | ------------------------------------------------------------- |
| must_succeed | bool   | false   | will try running this command until it completes successfully |
| command      | string |         | command to execute                                            |

## Provider Configuration

### Elephant Calc

Perform calculation and unit-conversions.

#### Features

- save results
- copy results

#### Requirements

- `libqalculate`
- `wl-clipboard`

#### Usage

Refer to the official [libqalculate docs](https://github.com/Qalculate/libqalculate).

`~/.config/elephant/calc.toml`

#### Config

| Field                  | Type   | Default              | Description                                                         |
| ---------------------- | ------ | -------------------- | ------------------------------------------------------------------- |
| icon                   | string | depends on provider  | icon for provider                                                   |
| name_pretty            | string | depends on provider  | displayed name for the provider                                     |
| min_score              | int32  | depends on provider  | minimum score for items to be displayed                             |
| hide_from_providerlist | bool   | false                | hides a provider from the providerlist provider. provider provider. |
| max_items              | int    | 100                  | max amount of calculation history items                             |
| placeholder            | string | calculating...       | placeholder to display for async update                             |
| require_number         | bool   | true                 | don't perform if query does not contain a number                    |
| min_chars              | int    | 3                    | don't perform if query is shorter than min_chars                    |
| command                | string | wl-copy -n '%VALUE%' | default command to be executed. supports %VALUE%.                   |
| async                  | bool   | true                 | calculation will be send async                                      |
| autosave               | bool   | false                | automatically save results                                          |

### Elephant Clipboard

Store clipboard history.

#### Features

- saves images and text history
- filter to show images only
- edit saved content
- localsend support
- pin items

#### Requirements

- `wl-clipboard`
- `imagemagick`

`~/.config/elephant/clipboard.toml`

#### Config

| Field                  | Type   | Default             | Description                                                                                        |
| ---------------------- | ------ | ------------------- | -------------------------------------------------------------------------------------------------- |
| icon                   | string | depends on provider | icon for provider                                                                                  |
| name_pretty            | string | depends on provider | displayed name for the provider                                                                    |
| min_score              | int32  | depends on provider | minimum score for items to be displayed                                                            |
| hide_from_providerlist | bool   | false               | hides a provider from the providerlist provider. provider provider.                                |
| max_items              | int    | 100                 | max amount of clipboard history items                                                              |
| image_editor_cmd       | string |                     | editor to use for images. use '%FILE%' as placeholder for file path.                               |
| text_editor_cmd        | string |                     | editor to use for text, otherwise default for mimetype. use '%FILE%' as placeholder for file path. |
| command                | string | wl-copy             | default command to be executed                                                                     |
| ignore_symbols         | bool   | true                | ignores symbols/unicode                                                                            |
| auto_cleanup           | int    | 0                   | will automatically cleanup entries entries older than X minutes                                    |

### Elephant Desktop Applications

Run installed desktop applications.

#### Features

- history
- pin items
- alias items
- auto-detect `uwsm`/`app2unit`

`~/.config/elephant/desktopapplications.toml`

#### Config

| Field                             | Type              | Default             | Description                                                                                                                                                                                          |
| --------------------------------- | ----------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| icon                              | string            | depends on provider | icon for provider                                                                                                                                                                                    |
| name_pretty                       | string            | depends on provider | displayed name for the provider                                                                                                                                                                      |
| min_score                         | int32             | depends on provider | minimum score for items to be displayed                                                                                                                                                              |
| hide_from_providerlist            | bool              | false               | hides a provider from the providerlist provider. provider provider.                                                                                                                                  |
| locale                            | string            |                     | to override systems locale                                                                                                                                                                           |
| action_min_score                  | int               | 20                  | min score for actions to be shown                                                                                                                                                                    |
| show_actions                      | bool              | false               | include application actions, f.e. 'New Private Window' for Firefox                                                                                                                                   |
| show_generic                      | bool              | true                | include generic info when show_actions is true                                                                                                                                                       |
| show_actions_without_query        | bool              | false               | show application actions, if the search query is empty                                                                                                                                               |
| history                           | bool              | true                | make use of history for sorting                                                                                                                                                                      |
| history_when_empty                | bool              | false               | consider history when query is empty                                                                                                                                                                 |
| only_search_title                 | bool              | false               | ignore keywords, comments etc from desktop file when searching                                                                                                                                       |
| icon_placeholder                  | string            | applications-other  | placeholder icon for apps without icon                                                                                                                                                               |
| aliases                           | map[string]string |                     | setup aliases for applications. Matched aliases will always be placed on top of the list. Example: 'ffp' => '<identifier>'. Check elephant log output when activating an item to get its identifier. |
| blacklist                         | []string          | <empty>             | blacklist desktop files from being parsed. Regexp.                                                                                                                                                   |
| window_integration                | bool              | false               | will enable window integration, meaning focusing an open app instead of opening a new instance                                                                                                       |
| ignore_pin_with_window            | bool              | true                | will ignore pinned apps that have an opened window                                                                                                                                                   |
| window_integration_ignore_actions | bool              | true                | will ignore the window integration for actions                                                                                                                                                       |
| wm_integration                    | bool              | false               | Moves apps to the workspace where they were launched at automatically. Currently Niri only.                                                                                                          |
| score_open_windows                | bool              | true                | Apps that have open windows, get their score halved. Requires window_integration.                                                                                                                    |
| single_instance_apps              | []string          | ["discord"]         | application IDs that don't ever spawn a new window.                                                                                                                                                  |

### Elephant Files

Find files/folders.

#### Features

- preview text/images/pdf
- open files, folders
- drag&drop files into other programs
- copy file/path
- support for localsend

#### Example `ignored_dirs`

```toml
ignored_dirs = ["/home/andrej/Documents/", "/home/andrej/Videos"]
```

#### Requirements

- `fd`

`~/.config/elephant/files.toml`

#### Config

| Field                  | Type                  | Default                                                    | Description                                                                   |
| ---------------------- | --------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------------------- |
| icon                   | string                | depends on provider                                        | icon for provider                                                             |
| name_pretty            | string                | depends on provider                                        | displayed name for the provider                                               |
| min_score              | int32                 | depends on provider                                        | minimum score for items to be displayed                                       |
| hide_from_providerlist | bool                  | false                                                      | hides a provider from the providerlist provider. provider provider.           |
| ignored_dirs           | []string              |                                                            | ignore these directories. regexp based.                                       |
| ignore_previews        | []main.IgnoredPreview |                                                            | paths will not have a preview                                                 |
| ignore_watching        | []string              |                                                            | paths will not be watched                                                     |
| search_dirs            | []string              | $HOME                                                      | directories to search for files                                               |
| fd_flags               | []string              | ['--ignore-vcs', '--type,' ,'file', '--type,' 'directory'] | flags for fd                                                                  |
| watch_buffer           | int                   | 2000                                                       | time in millisecnds elephant will gather changed paths before processing them |
| watch_dirs             | []string              | []                                                         | watch these dirs, even if watch = false                                       |
| watch                  | bool                  | false                                                      | watch indexed directories                                                     |

#### IgnoredPreview

| Field       | Type   | Default | Description                |
| ----------- | ------ | ------- | -------------------------- |
| path        | string |         | path to ignore preview for |
| placeholder | string |         | text to display instead    |

### Elephant Providerlist

Lists all installed providers and configured menus.

`~/.config/elephant/providerlist.toml`

#### Config

| Field                  | Type     | Default             | Description                                                         |
| ---------------------- | -------- | ------------------- | ------------------------------------------------------------------- |
| icon                   | string   | depends on provider | icon for provider                                                   |
| name_pretty            | string   | depends on provider | displayed name for the provider                                     |
| min_score              | int32    | depends on provider | minimum score for items to be displayed                             |
| hide_from_providerlist | bool     | false               | hides a provider from the providerlist provider. provider provider. |
| hidden                 | []string | <empty>             | hidden providers                                                    |

### Elephant Symbols

Search for emojis and symbols

#### Requirements

- `wl-clipboard`

#### Possible locales

af,ak,am,ar,ar_SA,as,ast,az,be,bew,bg,bgn,blo,bn,br,bs,ca,ca_ES,ca_ES_VALENCIA,ccp,ceb,chr,ckb,cs,cv,cy,da,de,de_CH,doi,dsb,el,en,en_001,en_AU,en_CA,en_GB,en_IN,es,es_419,es_MX,es_US,et,eu,fa,ff,ff_Adlm,fi,fil,fo,fr,fr_CA,frr,ga,gd,gl,gu,ha,ha_NE,he,hi,hi_Latn,hr,hsb,hu,hy,ia,id,ig,is,it,ja,jv,ka,kab,kk,kk_Arab,kl,km,kn,ko,kok,ku,ky,lb,lij,lo,lt,lv,mai,mi,mk,ml,mn,mni,mr,ms,mt,my,ne,nl,nn,no,nso,oc,om,or,pa,pa_Arab,pap,pcm,pl,ps,pt,pt_PT,qu,quc,rhg,rm,ro,root,ru,rw,sa,sat,sc,sd,si,sk,sl,so,sq,sr,sr_Cyrl,sr_Cyrl_BA,sr_Latn,sr_Latn_BA,su,sv,sw,sw_KE,ta,te,tg,th,ti,tk,tn,to,tr,tt,ug,uk,ur,uz,variations.txt,vec,vi,wo,xh,yo,yo_BJ,yue,yue_Hans,zh,zh_Hant,zh_Hant_HK,zu,

`~/.config/elephant/symbols.toml`

#### Config

| Field                  | Type   | Default             | Description                                                         |
| ---------------------- | ------ | ------------------- | ------------------------------------------------------------------- |
| icon                   | string | depends on provider | icon for provider                                                   |
| name_pretty            | string | depends on provider | displayed name for the provider                                     |
| min_score              | int32  | depends on provider | minimum score for items to be displayed                             |
| hide_from_providerlist | bool   | false               | hides a provider from the providerlist provider. provider provider. |
| locale                 | string | en                  | locale to use for symbols                                           |
| history                | bool   | true                | make use of history for sorting                                     |
| history_when_empty     | bool   | false               | consider history when query is empty                                |
| command                | string | wl-copy             | default command to be executed. supports %VALUE%.                   |

### Elephant Websearch

Search the web with custom defined search engines.

#### Example entry

```toml
[[entries]]
default = true
name = "Google"
url = "https://www.google.com/search?q=%TERM%"
```

`~/.config/elephant/websearch.toml`

#### Config

| Field                  | Type          | Default             | Description                                                         |
| ---------------------- | ------------- | ------------------- | ------------------------------------------------------------------- |
| icon                   | string        | depends on provider | icon for provider                                                   |
| name_pretty            | string        | depends on provider | displayed name for the provider                                     |
| min_score              | int32         | depends on provider | minimum score for items to be displayed                             |
| hide_from_providerlist | bool          | false               | hides a provider from the providerlist provider. provider provider. |
| entries                | []main.Engine | google              | entries                                                             |
| history                | bool          | true                | make use of history for sorting                                     |
| history_when_empty     | bool          | false               | consider history when query is empty                                |
| engines_as_actions     | bool          | true                | run engines as actions                                              |
| always_show_default    | bool          | true                | always show the default search engine when queried                  |
| text_prefix            | string        | Search:             | prefix for the entry text                                           |
| command                | string        | xdg-open            | default command to be executed. supports %VALUE%.                   |

#### Engine

| Field   | Type   | Default | Description                                            |
| ------- | ------ | ------- | ------------------------------------------------------ |
| name    | string |         | name of the entry                                      |
| default | bool   |         | entry to display when querying multiple providers      |
| prefix  | string |         | prefix to actively trigger this entry                  |
| url     | string |         | url, example: 'https://www.google.com/search?q=%TERM%' |
| icon    | string |         | icon to display, fallsback to global                   |
