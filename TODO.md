# TODO

- [x] When collapsed only show the number of tabs that have updates - Medium
- [x] Need a shortcut for duplicate tab - Medium. Done via settings
- [x] When cycling through tab, don't cycle through collapsed tabs in a group - High
- [ ] When cycling through collapsed group, need to land on the header and have shortcuts to collapse/expand the group - Low priority/High effort
- [x] When closing the last tab in a group, the group disappears but it is still shown in "Add To Group". Potentially it's not removed from the metadata array. - LOW
- [x] When collapsed, the status spinning wheels of the group tabs still showings - LOW
- [ ] Find URLs must find all OSC8 links - Medium | Medium
- [x] Fix notifications
- [ ] Fix marks and annotations
- [ ] Fix Claude integration
- [x] In minimal mode, the tab background is the same as the editor background which is good. However the border around tab and main editor remains black. I want to change it to be the same as the tab color. If the tab is inside a group, use the group color. Medium | Medium
- [ ] Update the python api that create a new session to have an optional parameter group_id. When provided, group_id will be validated if it's a valid existing group ID. If valid then the new session will be added to the same group (similar behavior to the Duplicate Tab behaviour)
- [x] currently all groups will have the same prominent level of their color. Update the code so that the prominent level is only applied to inactive groups. For active group the prominent level is set to 1 (full prominence).
- [ ] make the surrounding boundary of active tab thicker and brighter
