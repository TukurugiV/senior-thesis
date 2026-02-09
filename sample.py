def greet(name):
    """
    A simple function to greet the user by name.
    """
    return f"Hello, {name}! Welcome to the sample program."

def add_numbers(a, b):
    """
    A simple function to add two numbers.
    """
    return a + b

def main():
    """
    Main function to demonstrate the sample program.
    """
    name = input("Enter your name: ")
    print(greet(name))
    
    print("\nLet's add two numbers!")
    num1 = float(input("Enter the first number: "))
    num2 = float(input("Enter the second number: "))
    print(f"The sum of {num1} and {num2} is {add_numbers(num1, num2)}.")

if __name__ == "__main__":
    main()