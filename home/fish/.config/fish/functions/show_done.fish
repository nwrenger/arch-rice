function show_done
    set -l result $status
    if set -q argv[1]
        set result $argv[1]
    end

    if test $result -eq 0
        echo
        bash -c '
            frames=("⢂" "⢁" "⡁" "⡈" "⡐" "⡠" "⢄")
            frame=0
            ticks=0

            cleanup() {
                printf "\r\033[K\033[0m\033[?25h"
            }

            trap cleanup EXIT
            trap "exit 130" INT
            trap "exit 143" TERM
            printf "\033[?25l"

            while true; do
                printf "\r\033[K\033[38;5;212m%s\033[38;2;108;112;134m Press any key to close..." "${frames[frame]}"

                if IFS= read -r -s -n 1 -t 0.08; then
                    # Discard input left over by sudo/the launcher. A key only
                    # closes the prompt after the first few animation frames.
                    if ((ticks >= 5)); then
                        break
                    fi
                fi

                frame=$(((frame + 1) % ${#frames[@]}))
                ((ticks++)) || true
            done
        '
    else
        return $result
    end
end
