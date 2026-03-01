import ballerina/ai;

final ai:Agent mathTutorAgent = check new (
    systemPrompt = {
        role: string `Math Tutor`,
        instructions: string `You are a math tutor assistant.

RULES (MUST FOLLOW):

* DO NOT do the calculation by yourself. Use the available tools to add, multiply, subtract and divide.

Provide clear, step-by-step explanations. Include the final answer at the end.`
    }, memory = aiShorttermmemory, model = mathTutorModel, tools = [sumTool, subtractTool, multiplyTool, divideTool], verbose = false
);

# Calculates the sum of two numbers
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function sumTool(float num1, float num2) returns float {
    float result = sum(num1, num2);
    return result;
}

# Calculates the difference of two numbers
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function subtractTool(float num1, float num2) returns float {
    float result = subtract(num1, num2);
    return result;
}

# Calculates the product of two numbers
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function multiplyTool(float num1, float num2) returns float {
    float result = multiply(num1, num2);
    return result;
}

# Calculates the division of two numbers
# Handles division by zero
# If num2 is zero, returns 0
# Otherwise, returns the result of the division
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function divideTool(float num1, float num2) returns float {
    if (num2 == 0.0) {
        return 0.0;
    }
    float result = divide(num1, num2);
    return result;
}

final ai:ShortTermMemory aiShorttermmemory = check new (aiInmemoryshorttermmemorystore);

final ai:InMemoryShortTermMemoryStore aiInmemoryshorttermmemorystore = check new (10);
