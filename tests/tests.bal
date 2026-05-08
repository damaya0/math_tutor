import ballerina/ai;
import ballerina/test;

isolated function loadEvalsetData() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/math-tutor.evalset.json");
}

isolated function loadEvalsetData1() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/math-tutor.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadEvalsetData1
}
function testToolTrajectory(ai:ConversationThread thread) returns error? {
    foreach ai:Trace trace in thread.traces {
        ai:Trace actualTrace = check mathTutorAgent.run(string `${trace.userMessage.content.toString()}`, string `${thread.id}`);
        test:assertEquals(actualTrace.toolCalls, trace.toolCalls);
    }

}
