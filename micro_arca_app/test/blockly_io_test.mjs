// Run with Node.js: node test/blockly_io_test.mjs
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const root = new URL('../assets/blockly/', import.meta.url);
const context = vm.createContext({ console, setTimeout, clearTimeout });
for (const file of ['blockly_compressed.js', 'blocks_compressed.js', 'python_compressed.js', 'pt-br.js', 'io_blocks.js']) {
  vm.runInContext(fs.readFileSync(new URL(file, root), 'utf8'), context, { filename: file });
}
const html = fs.readFileSync(new URL('index.html', root), 'utf8');
const script = html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
vm.runInContext(script.slice(0, script.indexOf('      const theme =')), context);
vm.runInContext(`
  globalThis.testAPI = { Blockly, pythonGenerator, registerLibraryManifests, MicroArcaIO };
`, context);
const { Blockly, pythonGenerator, registerLibraryManifests, MicroArcaIO } = context.testAPI;
let checks = 0;
export const generatedPrograms = [];
function workspace() { return new Blockly.Workspace(); }
function defaults(block) {
  for (const [name, value] of Object.entries(MicroArcaIO.defaults[block.type] || {})) {
    const number = block.workspace.newBlock('math_number');
    number.setFieldValue(String(value), 'NUM');
    block.getInput(name).connection.connect(number.outputConnection);
  }
  return block;
}
for (const type of MicroArcaIO.types) {
  const ws = workspace();
  const b = defaults(ws.newBlock(type));
  const code = pythonGenerator.workspaceToCode(ws);
  generatedPrograms.push(code);
  assert.match(code, /from machine import Pin, ADC, PWM/);
  assert.match(code, /finally:\n\s+_microarca_finalizar_pwm\(\)/);
  assert.doesNotMatch(code, /undefined|NaN/);
  const saved = Blockly.serialization.workspaces.save(ws);
  const reloaded = workspace();
  Blockly.serialization.workspaces.load(saved, reloaded);
  assert.equal(pythonGenerator.workspaceToCode(reloaded), code);
  if (type === 'microarca_pin_read') assert.equal(b.outputConnection.getCheck()[0], 'Boolean');
  if (type === 'microarca_analog_read') assert.equal(b.outputConnection.getCheck()[0], 'Number');
  ws.dispose(); reloaded.dispose(); checks++;
}
{
  const ws = workspace();
  const print = ws.newBlock('text_print');
  const input = ws.newBlock('microarca_console_input');
  const prompt = ws.newBlock('text');
  prompt.setFieldValue('Qual é seu nome? ', 'TEXT');
  input.getInput('PROMPT').connection.connect(prompt.outputConnection);
  print.getInput('TEXT').connection.connect(input.outputConnection);
  const code = pythonGenerator.workspaceToCode(ws);
  assert.match(code, /print\(input\(['"]Qual é seu nome\? ['"]\)\)/);
  const saved = Blockly.serialization.workspaces.save(ws);
  const restored = workspace();
  Blockly.serialization.workspaces.load(saved, restored);
  assert.equal(pythonGenerator.workspaceToCode(restored), code);
  ws.dispose(); restored.dispose(); checks++;
}
{
  const ws = workspace();
  const condition = ws.newBlock('controls_if');
  const digital = defaults(ws.newBlock('microarca_pin_read'));
  condition.getInput('IF0').connection.connect(digital.outputConnection);
  assert.equal(condition.getInputTargetBlock('IF0'), digital);
  const code = pythonGenerator.workspaceToCode(ws);
  assert.match(code, /if bool\(_microarca_obter_pino\(4, Pin.IN\).value\(\)\):/);
  const pwm = defaults(ws.newBlock('microarca_pwm_write'));
  assert.equal(ws.connectionChecker.canConnect(digital.outputConnection, pwm.getInput('DUTY').connection, false), false);
  ws.dispose(); checks++;
}
{
  // A declarative dropdown is emitted as a Python string, never as raw code.
  registerLibraryManifests([{
    package: { id: 'buzzer-passivo', version: '1.0.0' },
    category: { name: 'Buzzer', color: '#9C4DCC' },
    blocks: [{ type: 'buzzer_passivo_test', label: 'nota {NOTA}', description: 'test',
      fields: [{ name: 'NOTA', type: 'dropdown', default: 'A', options: [['Lá', 'A'], ['Dó', 'C']] }],
      python: { imports: ['from lib_buzzer_passivo import criar_buzzer'], template: 'print({NOTA})\n' },
    }],
  }]);
  const ws = workspace();
  const b = ws.newBlock('buzzer_passivo_test');
  b.setFieldValue('C', 'NOTA');
  const code = pythonGenerator.workspaceToCode(ws);
  assert.match(code, /print\('C'\)/);
  assert.match(code, /finally:\n\s+_microarca_parar_buzzers\(\)/);
  ws.dispose(); checks++;
}
console.log(`${checks} Blockly IO/generator checks passed`);

export function checkLibraryManifest(manifest) {
  registerLibraryManifests([manifest]);
  const ws = workspace();
  let previous;
  for (const definition of manifest.blocks) {
    const b = ws.newBlock(definition.type);
    for (const field of definition.fields) {
      if (field.type === 'integer') {
        const n = ws.newBlock('math_number');
        n.setFieldValue(String(field.default), 'NUM');
        b.getInput(field.name).connection.connect(n.outputConnection);
      } else {
        b.setFieldValue(field.default, field.name);
      }
    }
    if (previous) previous.nextConnection.connect(b.previousConnection);
    previous = b;
  }
  const code = pythonGenerator.workspaceToCode(ws);
  assert.match(code, /buzzer = criar_buzzer/);
  assert.match(code, /buzzer.tocar_nota\('A'/);
  assert.match(code, /_microarca_parar_buzzers\(\)/);
  const saved = Blockly.serialization.workspaces.save(ws);
  const restored = workspace();
  Blockly.serialization.workspaces.load(saved, restored);
  assert.equal(pythonGenerator.workspaceToCode(restored), code);
  ws.dispose(); restored.dispose();
  return code;
}
