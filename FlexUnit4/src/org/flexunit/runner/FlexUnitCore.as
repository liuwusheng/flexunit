/**
 * Copyright (c) 2009 Digital Primates IT Consulting Group
 * 
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 * 
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 * 
 * @author     Michael Labriola 
 * @version    
 **/ 
package org.flexunit.runner {
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.utils.*;
	
	import org.flexunit.IncludeFlexClasses;
	import org.flexunit.experimental.theories.Theories;
	import org.flexunit.runner.notification.Failure;
	import org.flexunit.runner.notification.IAsyncStartupRunListener;
	import org.flexunit.runner.notification.IRunListener;
	import org.flexunit.runner.notification.IRunNotifier;
	import org.flexunit.runner.notification.RunListener;
	import org.flexunit.runner.notification.RunNotifier;
	import org.flexunit.runner.notification.async.AsyncListenerWatcher;
	import org.flexunit.token.AsyncListenersToken;
	import org.flexunit.token.AsyncTestToken;
	import org.flexunit.token.ChildResult;
	import org.flexunit.utils.ClassNameUtil;

	/**  
	 * FlexUnit4 Version: 4.0.0b2<p>
	 * 
	 * The <code>FlexUnitCore</code> is responsible for executing objects that implement an <code>IRequest</code>
	 * interface.  There are several ways that the <code>IRequest</code> can be provided to the 
	 * <code>FlexUnitCore</code>.  If you pass FlexUnit4’s core anything other than an <code>IRequest</code>, the 
	 * core uses these methods to generate a <code>Request</code> object before processing continues.<p>
	 * 
	 * Ways that an <code>IRequest</code> can be provided to the <code>FlexUnitCore</code> are as follows:
	 * <ul>
	 * <li> A group of arguments of arguments can be provided to the <code>#run</code> method which will
	 * eventaully create an <code>IRequest</code>.
	 * <li> A group of classes consisting of suites and test cases to run can be provided to the 
	 * <code>#runClasses()</code>  method to generate an <code>IRequest</code>.
	 * <li> An <code>IRequest</code> can be passed directly to the <code>#runRequest()</code> method.
	 * <code>IRequest</code>s can be generated by calling static methods that create <code>IRequests</code>
	 * in the <code>Request</code> class.
	 * </ul><p>
	 * 
	 * Ultimately, FlexUnit4 runs one and only one request per run. So, if you pass it multiple classes, etc. 
	 * these are all wrapped in a single <code>Request</code> before execution begins.  Once the 
	 * <code>IRequest</code> has been provided to the <code>FlexUnitCore</code>, the test run will begin
	 * once all <code>IRunListener</code> are ready.<p>
	 * 
	 * In order to add an <code>IRunListener</code> to the test run, the <code>#addListener()</code> method must 
	 * called.  If one wishes to remove a listener from the test run, the <code>#removeListener()</code> method
	 * needs to be called with <code>IRunListener</code> to remove.<p>
	 * 
	 * Once the test run has finished execution, a <code>Result</code> will be obtained and the <code>IRunListener</code>s
	 * will be notified of the results of the test run.
	 * 
	 * @see org.flexunit.runner.Request
	 * @see org.flexunit.runner.Result
	 * @see org.flexunit.runner.notification.IRunListener
	 */

	public class FlexUnitCore extends EventDispatcher {
		// We have a toggle in the compiler arguments so that we can choose whether or not the flex classes should
		// be compiled into the FlexUnit swc.  For actionscript only projects we do not want to compile the
		// flex classes since it will cause errors.
		CONFIG::useFlexClasses {
			// This class imports all Flex classes.
			/**
			 * @private
			 */
			private var t1:IncludeFlexClasses;
		}
		
		/**
		 * @private
		 */
		private var notifier:IRunNotifier;
		/**
		 * @private
		 */
		private var asyncListenerWatcher:AsyncListenerWatcher;
		
		/**
		 * @private
		 */
		private static const RUN_LISTENER:String = "runListener";
		public static const TESTS_COMPLETE : String = "testsComplete";
		public static const RUNNER_START : String = "runnerStart";
		public static const RUNNER_COMPLETE : String = "runnerComplete";

		//Just keep theories linked in until we decide how to deal with it
		/**
		 * @private
		 */
		private var theory:Theories;
		
		/**
		 * Returns the version number.
		 */
		public static function get version():String {
			return "4.0.0b2";
		}

		private function dealWithArgArray( ar:Array, foundClasses:Array, missingClasses:Array ):void {
			for ( var i:int=0; i<ar.length; i++ ) {
				try {
					if ( ar[ i ] is String ) {
						foundClasses.push( getDefinitionByName( ar[ i ] ) ); 
					} else if ( ar[ i ] is Array ) {
						dealWithArgArray( ar[ i ] as Array, foundClasses, missingClasses );
					} else if ( ar[ i ] is IRequest ) {
						foundClasses.push( ar[ i ] ); 
					} else if ( ar[ i ] is Class ) {
						foundClasses.push( ar[ i ] ); 
					} else if ( ar[ i ] is Object ) {
						//this is actually likely an instance.
						//eventually we intend to have more evolved support for
						//this, but, for right now, just try to make it a class
						var className:String = getQualifiedClassName( ar[ i ] );
						var definition:* = getDefinitionByName( className );
						foundClasses.push( definition );
					}
				}
				catch ( error:Error ) {
					//logger.error( "Cannot find class {0}", ar[i] ); 
					var desc:IDescription = Description.createSuiteDescription( ar[ i ] );
					var failure:Failure = new Failure( desc, error );
					missingClasses.push( failure );
				}
			}
		}

		/**
		 * Determines what classes can be found in the provided <code>args</code>.  If any classes 
		 * have been reported but are missing, those classes will be reported as failures in the returned
		 * <code>Result</code>.  The classes that are found in the arguments will be wrapped into a
		 * <code>Request</code>, and that <code>Request</code> will be used for the test run.
		 * 
		 * @param args The arguments are provided for the test run.
		 * @return a <code>Result</code> describing the details of the test run and the failed tests.
		 */
		public function run( ...args ):Result {
			var foundClasses:Array = new Array();
			//Unlike JUnit, missing classes is probably unlikely here, but lets preserve the metaphor
			//just in case
			var missingClasses:Array = new Array();
			
			dealWithArgArray( args, foundClasses, missingClasses );

			var result:Result = runClasses.apply( this, foundClasses );
			
			for ( var i:int=0; i<missingClasses.length; i++ ) {
				result.failures.push( missingClasses[ i ] );
			}
			
			return result;
		}

		/**
		 * Wraps the class arguments contained in <code>args</code> into a <code>Request</code>.
		 * The classes that are found in the arguments will be wrapped into a
		 * <code>Request</code>, and that <code>Request</code> will be used for the test run.
		 * 
		 * @param args The class arguments that are provided for the test run.
		 */
		public function runClasses( ...args ):void {
			runRequest( Request.classes.apply( this, args ) );
		}
		
		/**
		 * Runs the classes contained in the <code>Request</code> using the <code>IRunner</code> of 
		 * the <code>Request</code>.  Feedback will be written while the tests
		 * are running and stack traces writes will be made for all failed tests after all tests 
		 * complete.
		 * 
		 * @param request The <code>Request</code> describing the <code>IRunner</code> to use for
		 * for the test run.
		 */
		public function runRequest( request:Request ):void {
			runRunner( request.iRunner )
		}
		
		/**
		 * Runs the tests contained in <code>IRunner</code> if all <code>IAsyncStartupRunListerners</code>
		 * are ready; otherwise, the the test run will begin once all listeners have reported that they
		 * are ready.<p>
		 * 
		 * Once the test run begins, feedback will be written while the tests are running and stack traces 
		 * writes will be made for all failed tests after all tests complete.
		 * 
		 * @param runner The <code>IRunner</code> to use for this test run.
		 */
		public function runRunner( runner:IRunner ):void {
			if ( asyncListenerWatcher.allListenersReady ) {
				beginRunnerExecution( runner );
			} else {
				//we need to wait until all listeners are ready (or failed) before we can continue
				var token:AsyncListenersToken = asyncListenerWatcher.startUpToken;
				token.runner = runner;
				token.addNotificationMethod( beginRunnerExecution );
			}
		}
		
		/**
		 * Starts the execution of the <code>IRunner</code>.
		 */
		protected function beginRunnerExecution( runner:IRunner ):void {
			var result:Result = new Result();
			var runListener:RunListener = result.createListener();
			addFirstListener( runListener );

			var token:AsyncTestToken = new AsyncTestToken( ClassNameUtil.getLoggerFriendlyClassName( this ) );
			token.addNotificationMethod( handleRunnerComplete );
			token[ RUN_LISTENER ] = runListener;

			dispatchEvent( new Event( RUNNER_START ) );

			try {
				notifier.fireTestRunStarted( runner.description );
				runner.run( notifier, token );
			}
			
			catch ( error:Error ) {
				//I think we need to further restrict the case where this is true
				notifier.fireTestAssumptionFailed( new Failure( runner.description, error ) );

				finishRun( runListener );
			}
		}
		
		/**
		 * All tests have finished execution.
		 */
		private function handleRunnerComplete( result:ChildResult ):void {
			var runListener:RunListener = result.token[ RUN_LISTENER ];

			finishRun( runListener );
		}
		
		/**
		 * Notifies that the <code>runListener</code> that the test run has finished.
		 * 
		 * @param runListener The listern to notify about the test run finishing.
		 */
		private function finishRun( runListener:RunListener ):void {
			notifier.fireTestRunFinished( runListener.result );
			removeListener( runListener );
			
			dispatchEvent( new Event( TESTS_COMPLETE ) );
		}

		/**
		 * Add a listener to be notified as the tests run.
		 * @param listener the listener to add
		 * @see org.flexunit.runner.notification.RunListener
		 */
		public function addListener( listener:IRunListener ):void {
			notifier.addListener( listener );
			if ( listener is IAsyncStartupRunListener ) {
				asyncListenerWatcher.watchListener( listener as IAsyncStartupRunListener );
			}
		}

		private function addFirstListener( listener:IRunListener ):void {
			notifier.addFirstListener( listener );
			if ( listener is IAsyncStartupRunListener ) {
				asyncListenerWatcher.watchListener( listener as IAsyncStartupRunListener );
			}
		}

		/**
		 * Remove a listener.
		 * @param listener the listener to remove
		 */
		public function removeListener( listener:IRunListener ):void {
			notifier.removeListener( listener );

			if ( listener is IAsyncStartupRunListener ) {
				asyncListenerWatcher.unwatchListener( listener as IAsyncStartupRunListener );
			}			
		}
		
		protected function handleAllListenersReady( event:Event ):void {
			
		}
		
		/**
		 * Create a new <code>FlexUnitCore</code> to run tests.
		 */
		public function FlexUnitCore() {
			notifier = new RunNotifier();
			
			asyncListenerWatcher = new AsyncListenerWatcher( notifier, null );
			//asyncListenerWatcher.addEventListener( AsyncListenerWatcher.ALL_LISTENERS_READY, handleAllListenersReady, false, 0, true );
		}
	}
}