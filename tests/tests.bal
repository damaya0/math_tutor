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
    minPassRate: 0.4,
    dataProvider: loadEvalsetData2
}
function MathTuteEval(ai:ConversationThread thread) returns error? {
    foreach ai:Trace trace in thread.traces {
        ai:Trace actualTrace = check mathTutorAgent.run(trace.userMessage.content.toString(), "thread.id");
        test:assertEquals(actualTrace.toolCalls, trace.toolCalls);
    }
}

isolated function loadEvalsetData3() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests\\resources\\evalsets\\mathtutor1.evalset.json");
}

final ai:Wso2ModelProvider aiWso2modelprovider = check ai:getDefaultModelProvider();

@test:Config {
    groups: ["evaluations"],
    dependsOn: [],
    minPassRate: 0.9,
    dataProvider: loadEvalsetData3
}
function LLMJudge(ai:ConversationThread thread) returns error? {
    float passingScore = 0.8;
    foreach ai:Trace trace in thread.traces {
        ai:Trace actualTrace = check mathTutorAgent.run(trace.userMessage.content.toString(), thread.id);
        float td = check aiWso2modelprovider->generate(`you are a LLM that judges an agent. Be very harsh. Penalize any differences between the ideal output and real ouput. 

Here is the ideal output - ${check trace.output}
Here is the real output -  ${check actualTrace.output}

Give a score between 0 to 1 based on your evaluation. 0 if the real output is extremely different, and 1 if the output is exactly similar. Don't give 1 even if even a single character differs from the ideal answer.`);
        test:assertEquals(true, td >= passingScore);
    }
}


