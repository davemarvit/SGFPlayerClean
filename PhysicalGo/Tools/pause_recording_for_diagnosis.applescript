-- Stop diagnostic image saving and warning feedback; leave game/clock state alone.
-- Intended for the assistant's first action after the user reports a failure.
tell application "System Events"
    if not (exists process "Physical Go") then return "Physical Go is not running."
    tell process "Physical Go"
        if not (exists window 1) then error "Open Physical Go's window before pausing diagnostic collection."
        -- SwiftUI exposes the header's Info button without an AX title.
        if not (exists sheet 1 of window 1) then click button 1 of group 1 of window 1
        click radio button 2 of radio group 1 of group 1 of sheet 1 of window 1
        set s to scroll area 1 of group 1 of sheet 1 of window 1
        if value of checkbox "Diagnostics mode" of s is 1 then click checkbox "Diagnostics mode" of s
        if value of checkbox 2 of group 2 of s is 1 then error "Next-game recording remains armed."
        if value of checkbox 1 of group 2 of s is 1 then error "Continuous recording is still active."
        click radio button 1 of radio group 1 of group 1 of sheet 1 of window 1
        set g to group 1 of scroll area 1 of group 1 of sheet 1 of window 1
        if not (exists pop up button 1 of g) then
            if role of UI element 29 of g is not "AXDisclosureTriangle" then error "Recording feedback controls have moved."
            click UI element 29 of g
        end if
        set p to pop up button 1 of g
        click p
        click menu item "Off" of menu 1 of p
        if value of p is not "Off" then error "Warning feedback is still enabled."
        click button 1 of group 1 of sheet 1 of window 1
    end tell
end tell
return "Image saving and warning feedback are off. Game and clock state were not changed."
