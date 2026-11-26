// Geração real do Blockly, persistência e execução do Python sem hardware.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { Blockly, pythonGenerator } from './blockly_io_test.mjs';

const python = process.env.PYTHON || (process.platform === 'win32' ? 'python' : 'python3');
function execute(code) {
  return execFileSync(python, ['-c', code], { encoding: 'utf8', timeout: 5000 }).trim();
}
function number(ws, value) {
  const block = ws.newBlock('math_number');
  block.setFieldValue(String(value), 'NUM');
  return block;
}
function variable(ws, id) {
  const block = ws.newBlock('variables_get_dynamic');
  block.setFieldValue(id, 'VAR');
  return block;
}

// A condição é reavaliada, o laço termina e o bloco seguinte é executado.
{
  const ws = new Blockly.Workspace();
  const id = ws.getVariableMap().createVariable('contador', 'Number').getId();
  const start = ws.newBlock('variables_set_dynamic');
  start.setFieldValue(id, 'VAR');
  start.getInput('VALUE').connection.connect(number(ws, 0).outputConnection);
  const loop = ws.newBlock('microarca_while');
  const condition = ws.newBlock('logic_compare');
  condition.setFieldValue('LT', 'OP');
  condition.getInput('A').connection.connect(variable(ws, id).outputConnection);
  condition.getInput('B').connection.connect(number(ws, 3).outputConnection);
  loop.getInput('BOOL').connection.connect(condition.outputConnection);
  const change = ws.newBlock('microarca_variable_change');
  change.setFieldValue(id, 'VAR');
  change.getInput('DELTA').connection.connect(number(ws, 1).outputConnection);
  loop.getInput('DO').connection.connect(change.previousConnection);
  start.nextConnection.connect(loop.previousConnection);
  const print = ws.newBlock('text_print');
  print.getInput('TEXT').connection.connect(variable(ws, id).outputConnection);
  loop.nextConnection.connect(print.previousConnection);
  const code = pythonGenerator.workspaceToCode(ws);
  assert.match(code, /while contador < 3:/);
  assert.equal(execute(code), '3');
  const restored = new Blockly.Workspace();
  Blockly.serialization.workspaces.load(Blockly.serialization.workspaces.save(ws), restored);
  assert.equal(pythonGenerator.workspaceToCode(restored), code);
  assert.equal(execute(pythonGenerator.workspaceToCode(restored)), '3');
  ws.dispose(); restored.dispose();
}

// Condição inicialmente falsa: nenhuma execução do corpo; prossegue normalmente.
{
  const ws = new Blockly.Workspace();
  const loop = ws.newBlock('microarca_while');
  const low = ws.newBlock('microarca_logic_level');
  low.setFieldValue('LOW', 'LEVEL');
  loop.getInput('BOOL').connection.connect(low.outputConnection);
  const inside = ws.newBlock('text_print');
  const text = ws.newBlock('text');
  text.setFieldValue('nao deve aparecer', 'TEXT');
  inside.getInput('TEXT').connection.connect(text.outputConnection);
  loop.getInput('DO').connection.connect(inside.previousConnection);
  const after = ws.newBlock('text_print');
  after.getInput('TEXT').connection.connect(number(ws, 42).outputConnection);
  loop.nextConnection.connect(after.previousConnection);
  assert.equal(execute(pythonGenerator.workspaceToCode(ws)), '42');
  const wrongType = number(ws, 1);
  assert.equal(ws.connectionChecker.canConnect(wrongType.outputConnection, loop.getInput('BOOL').connection, false), false);
  ws.dispose();
}

// Bloco vazio gera Python válido e não inicia um laço infinito por omissão.
{
  const ws = new Blockly.Workspace();
  ws.newBlock('microarca_while');
  const code = pythonGenerator.workspaceToCode(ws);
  assert.match(code, /while False:\n\s+pass/);
  assert.equal(execute(code), '');
  ws.dispose();
}
console.log('3 verificações de repetir enquanto aprovadas (incluindo execução de Python).');
