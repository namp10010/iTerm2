# Restore verbosity

When a tab/session is restore, it adds a lot of text to the output.

```
%
Session Contents Restored on 7 May 2026 at 16:54
Last login: Thu May  7 16:54:02 on ttys005
%
Session Contents Restored on 7 May 2026 at 17:12
Last login: Thu May  7 17:12:41 on ttys005
%
Session Contents Restored on 8 May 2026 at 21:33
Last login: Fri May  8 21:33:25 on ttys003
%
Session Contents Restored on 10 May 2026 at 20:16
Last login: Sun May 10 20:16:08 on ttys004
%
Session Contents Restored on 15 May 2026 at 23:11
Last login: Fri May 15 23:11:13 on ttys003
```

Some sessions are restored multiple times and the above verbose output pollutes the output.

## Solution

Add an option to suppress this output.
