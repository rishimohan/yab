import Testing
@testable import Fast

/// `yab WORD` with a word that is no command used to start an agent task.
struct AgentCLIMistypedTests {
    @Test(arguments: [["tabs"], ["feedback", "--help"], ["feedback", "-h"], ["open", "tabs", "--help"], ["list-tabs"]])
    func mistypedCommandIsNotATask(words: [String]) {
        #expect(AgentCLI.mistyped(words) == words[0])
    }

    @Test(arguments: [["find the unread message from Alex in Slack"], ["summarize", "my", "tabs"],
                      ["Summarize"], ["what's new?"], ["https://example.com"], []])
    func sentencesStayTasks(words: [String]) {
        #expect(AgentCLI.mistyped(words) == nil)
    }
}
