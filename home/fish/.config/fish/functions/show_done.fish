function show_done
    if test $status -eq 0
        echo
        gum spin --spinner "jump" --title "Press any key to close..." \
            --title.foreground="#6c7086" -- bash -c 'read -n 1 -s'
    end
end
