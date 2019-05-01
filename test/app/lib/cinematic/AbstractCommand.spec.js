/* eslint-env jasmine */
import AbstractCommand, { run, cancel } from '../../../../app/views/play/cinematic/Command/AbstractCommand'
import { Noop, SyncFunction, SequentialCommands } from '../../../../app/views/play/cinematic/Command/commands'
import * as PromiseBB from 'bluebird'

PromiseBB.config({
  cancellation: true
})

class NaiveExtend extends AbstractCommand {}

class PassInRunCommand extends AbstractCommand {
  constructor (run) {
    super()
    this.run = run
  }
}

const simpleRunFunctions = [
  () => undefined,
  () => true,
  () => false,
  () => '',
  () => 'abc',
  () => {},
  () => ({ then: () => { } }), // Fake promise
  () => Promise.resolve() // non cancellable promise
]

describe('AbstractCommand', () => {
  it('abstract class can\'t be constructed', () => {
    expect(() => new AbstractCommand()).toThrow()
  })

  it('constructor works when extended', () => {
    expect(() => new NaiveExtend()).not.toThrow()
  })

  it('run method must be implemented', () => {
    expect(() => (new NaiveExtend()).run()).toThrow()
  })

  it('run must return a promise', () => {
    for (const fn of simpleRunFunctions) {
      expect(() => (new PassInRunCommand(fn))[run]()).toThrow()
    }
  })
})

describe('SyncFunction', () => {
  it('runs any function passed in', () => {
    for (const fn of simpleRunFunctions) {
      expect(() => (new SyncFunction(fn))[run]()).not.toThrow()
    }
  })

  it('not running command doesnt call function', () => {
    const functionSpy = jasmine.createSpy()
    const command = new SyncFunction(functionSpy)
    expect(functionSpy).not.toHaveBeenCalled()
    command[run]()
    expect(functionSpy).toHaveBeenCalledTimes(1)
  })
})

describe('SequentialCommands', () => {
  it('runs commands sequentially', done => {
    const functionSpy = jasmine.createSpy()
    const commands = [
      () => {
        expect(functionSpy).not.toHaveBeenCalled()
      },
      functionSpy,
      () => {
        expect(functionSpy).toHaveBeenCalledTimes(1)
      },
      done
    ]

    const commands2 = commands.map(f => new SyncFunction(f));

    (new SequentialCommands(commands2))[run]()
  })
})

describe('Noop command', () => {
  it('doesn\'t throw error when run', () => {
    expect(() => (new Noop())[run]()).not.toThrow()
  })
})