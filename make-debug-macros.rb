STATES = %w(
    TPStateSessionStopped
    TPStateSessionStopping
    TPStateSessionStarting
    TPStateSessionStarted
    TPStateSessionConfigurationFailed
    TPStateRecordingIdle
    TPStateRecordingStarted
    TPStateRecordingFirstStarting
    TPStateRecordingFirstStarted
    TPStateRecordingFirstCompleting
    TPStateRecordingFirstCompleted
    TPStateRecordingSecondStarting
    TPStateRecordingSecondStarted
    TPStateRecordingSecondCompleting
    TPStateRecordingSecondCompleted
    TPStateRecordingCompleted
)

template = '#define stateFor(enum) [@[%s] objectAtIndex:enum]'

# Need @"value1",@"value2",@"value3" for %s

puts (template % STATES.map { |s| '@' + '"' + s.sub('TPState', '') + '"'}.join(',') )

