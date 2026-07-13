import ballerina/ai;
import ballerina/test;

isolated function loadEvalsetData() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/math-tutor.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadEvalsetData
}
function testToolTrajectory(ai:ConversationThread thread) returns error? {
    foreach ai:Trace trace in thread.traces {
        ai:Trace actualTrace = check mathTutorAgent.run(string `${trace.userMessage.content.toString()}`, string `${thread.id}`);
        test:assertEquals(actualTrace.toolCalls, trace.toolCalls);
    }
}

isolated function loadEvalsetData1() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/mathtutor1.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadEvalsetData1
}
function FlowTester(ai:ConversationThread thread) returns error? {
}

isolated function loadEvalsetData2() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/mathtutor1.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    dependsOn: [],
    minPassRate: 0.9,
    dataProvider: loadEvalsetData2
}
function MathTuteEval(ai:ConversationThread thread) returns error? {
    foreach ai:Trace trace in thread.traces {
        ai:Trace actualTrace = check mathTutorAgent.run(trace.userMessage.content.toString(), "thread.id");
        test:assertEquals(actualTrace.toolCalls, trace.toolCalls);
    }
}

isolated function loadEvalsetData3() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests\resources\evalsets\mathtutor1.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    dependsOn: [],
    minPassRate: 0.9,
    dataProvider: loadEvalsetData3
}
function LLMJudge(ai:ConversationThread thread) returns error? {
}
