# TODO

1. [x] Update the python api that create a new session to have an optional parameter group_id. When provided, group_id will be validated if it's a valid existing group ID. If valid then the new session will be added to the same group (similar behavior to the Duplicate Tab behaviour)
2. [x] When collapsed only show the number of tabs that have updates - Medium
3. [x] Need a shortcut for duplicate tab - Medium. Done via settings
4. [x] When cycling through tab, don't cycle through collapsed tabs in a group - High
5. [ ] When cycling through collapsed group, need to land on the header and have shortcuts to collapse/expand the group - Low priority/High effort
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
17. [ ] Shift + Cmd + T (Cmd Z) didn't restore group and colours
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
28. [ ] Bug: when all the group are collapsed (folded) and you closed the last open tab, a tab is shown at the bottom of the tab bar "/var/folders/k3/4z6jyg6s3gv3t3k7f4yg1ls00000gn/T/6C679717-CAEE-47C7-B96F-9768A0CD3336-40343-00000C40A3329B30/pasted-image-20260524-161202.png".
29. [ ] Bug (not sure how to reproduce yet), sometimes you can't click to unfold currently folded tab groups.
