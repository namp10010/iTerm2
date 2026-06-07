# TODO

1. [x] Update the python api that create a new session to have an optional parameter group_id. When provided, group_id will be validated if it's a valid existing group ID. If valid then the new session will be added to the same group (similar behavior to the Duplicate Tab behaviour)
2. [x] When collapsed only show the number of tabs that have updates - Medium
3. [x] Need a shortcut for duplicate tab - Medium. Done via settings
4. [x] When cycling through tab, don't cycle through collapsed tabs in a group - High
5. [x] When cycling through collapsed group, need to land on the header and have shortcuts to collapse/expand the group - Low priority/High effort
6. [x] When closing the last tab in a group, the group disappears but it is still shown in "Add To Group". Potentially it's not removed from the metadata array. - LOW
7. [x] When collapsed, the status spinning wheels of the group tabs still showings - LOW
8. [ ] Find URLs must find all OSC8 links - Medium | Medium
9. [x] Fix notifications
10. [x] Fix marks and annotations
11. [x] Fix Claude integration
12. [x] In minimal mode, the tab background is the same as the editor background which is good. However the border around tab and main editor remains black. I want to change it to be the same as the tab color. If the tab is inside a group, use the group color. Medium | Medium
13. [x] currently all groups will have the same prominent level of their color. Update the code so that the prominent level is only applied to inactive groups. For active group the prominent level is set to 1 (full prominence).
14. [x] make the surrounding boundary of active tab thicker and brighter
15. [x] investigate the browser tab and how to run vscode plugin inside it
16. [x] a shortcuts to run quick command, similar to hotkey windows but use a sub-shell of the existing shell so it inherits the environment. I do like the composer but in composer when Shift+Enter it just send the text to existing session terminal. Won't do
17. [x] Shift + Cmd + T (Cmd Z) didn't restore group and colours
18. [x] When drag a tab to another group, the tab's group-id didn't get updated -> python sdk to duplicate the tab will make the newly duplicated tab to have the old group id and added to the old group
19. [x] When creating new session/tab using python sdk, add optional parameter to set the badge text.
20. [x] There are not much customisation available for the badge "/var/folders/k3/4z6jyg6s3gv3t3k7f4yg1ls00000gn/T/EB510465-D93F-4079-AA0A-9209EC1CC1BB-64599-00000558FEB9DCFB/pasted-image-20260506-154256.png". Redesign the badge so it looks less invasive and more professional
21. [x] Add option to not copy over the badge when duplicating a tab
22. [x] Add arg to window.async_create_tab() to create a new session in the background
23. [ ] When a group only has one tab, dropping a new tab onto it is very error prone due to the existing tab doesn't move to create a new placeholder between it and the leader.
24. [x] Similar to 21 but when Cmd + D to create a new pane splited horizontally
25. [x] Add another hotkey to add a tab to a new group which add a tab to a new group and automatically change focus to edit the name of the group
26. [x] The tab dedicated hot key Opt + CMD + number currently work for all tabs (including folded tabs in groups). It should only work on visible (unfolded) tabs
27. [ ] A hotkey to hide/show the badge. when it's hidden it should show a small mark in the top right corner where the badge used to be.
28. [x] Bug: when all the group are collapsed (folded) and you closed the last open tab, a tab is shown at the bottom of the tab bar "/var/folders/k3/4z6jyg6s3gv3t3k7f4yg1ls00000gn/T/6C679717-CAEE-47C7-B96F-9768A0CD3336-40343-00000C40A3329B30/pasted-image-20260524-161202.png".
29. [ ] Bug (not sure how to reproduce yet), sometimes you can't click to unfold currently folded tab groups.
30. [x] whenever my mac restart unexpectedly forcing my iTerm2 instance to quit, all running claude session are force-killed which leave no trace to restore them. this is different to a normal session exit where Claude would print out a session id to allow to restore. I want to update iTerm2 so that when a force-kill happens it will send a double Ctrl-D into the session or "/exit" + Enter. This should only happens when the foreground application is claude code.
31. [x] bug: group id for tab created via python sdk. when right click on the tab > remove from group > assign a new group, and then use python sdk to create a new session from that tab, the group id didn't seem to be update. this lead to when duplicate the tab, it is created in the old group. the python script I used to trigger this is "cc-new" from this repo "/Users/nam/work/ai/iterm-claude-orchestration"
32. [x] performance: at any point in time, I have way too many tabs open, some are in folded groups. this takes up a lot of memory. worse, each tab may have Claude code running and it spawns multiple process (prominently the golsp and other mcp server instances). I want to have an idle detection mechanism and a parking mechanism to kicks in when a tab is idle for a period of time (configureable). The mechanism is quite simple, it should remember the process tree that currently running. Then kill the whole tab (the autosave and restore mechanism should save the session info), when the tab is killed it will be come inactive (like a death shell), but it should not be removed. We need to keep an empty/death tab with minimal resource consumption as possible (similar to how Chrome browser auto memory saving for inatctive tabs). When user click on that tab, it should revive, this process can take some time but it's acceptable given the memory/cpu saving we gain by doing this.
33. [x] when the tab groups reached the highest number, the color stayed at red. adding new group will have the same bright red colours. we should be able to cycle through the full color list. also, we should add more colours to the pallets
34. [x] when restoring app from shutdown (Cmd + Q), the group status are not restored. for example, folded and unfolded group are not restored. also, active tab is not also restore (double check)
