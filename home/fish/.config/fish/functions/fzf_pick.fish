function fzf_pick
    # usage: fzf_pick <prompt_icon> <prompt_text> <preview_cmd> <source_cmd> [--single] [fzf options…]
    set icon $argv[1]
    set prompt $argv[2]
    set preview $argv[3]
    set source_cmd $argv[4]

    set multi_flag --multi
    set preview_label "alt-p: toggle  alt-j/k: scroll  tab: multi-select"
    set -l fzf_options
    for option in $argv[5..-1]
        if test "$option" = --single
            set multi_flag --no-multi
            set preview_label "alt-p: toggle  alt-j/k: scroll"
        else
            set -a fzf_options "$option"
        end
    end

    eval $source_cmd | fzf \
        --prompt="$icon $prompt > " \
        --ignore-case $multi_flag $fzf_options \
        --preview="$preview {1}" \
        --preview-label="$preview_label" \
        --preview-label-pos="bottom" \
        --preview-window="down:65%:wrap" \
        --bind="ctrl-c:abort,alt-p:toggle-preview" \
        --bind="alt-d:preview-half-page-down,alt-u:preview-half-page-up" \
        --bind="alt-k:preview-up,alt-j:preview-down" \
        --color="prompt:#cba6f7,pointer:#cba6f7,marker:#a6e3a1,hl:#89b4fa,hl+:#89b4fa"
end
