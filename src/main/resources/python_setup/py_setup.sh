# Install pyenv
curl https://pyenv.run | bash

# Set up your shell
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init -)"' >> ~/.bashrc
source ~/.bashrc

# Install Python 3.11.6
pyenv install 3.11.6

# Create both a pyenv version and virtual environment in one step with pyenv-virtualenv
pyenv virtualenv 3.11.6 project-3.11.6

# Activate it
pyenv activate project-3.11.6

# Or set it as the local version for your project directory
cd your-project-directory
pyenv local project-3.11.6